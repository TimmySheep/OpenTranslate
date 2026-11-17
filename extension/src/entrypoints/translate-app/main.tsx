/* eslint perfectionist/sort-imports: off -- static i18n initialization must precede config modules. */
import "./i18n"
import "@/utils/zod-config"
import type { Config } from "@/types/config/config"
import type { ProviderConfig } from "@/types/config/provider"
import type { ThemeMode } from "@/types/config/theme"
import { LANG_CODE_TO_EN_NAME, LANG_CODE_TO_LOCALE_NAME } from "@read-frog/definitions"
import { generateText } from "ai"
import { useEffect, useMemo, useRef, useState } from "react"
import { createRoot } from "react-dom/client"
import { z } from "zod"
import { configSchema } from "@/types/config/config"
import { isAPIProviderConfig, isLLMProviderConfig, isTranslateProviderConfig } from "@/types/config/provider"
import { enableAppSettingsMode } from "@/utils/app-settings-mode"
import { createBridgeAdapter, setStorageAdapter, storageAdapter } from "@/utils/atoms/storage-adapter"
import { CONFIG_STORAGE_KEY, DEFAULT_CONFIG, THEME_STORAGE_KEY } from "@/utils/constants/config"
import { getModelById } from "@/utils/providers/model"
import { resolveModelId } from "@/utils/providers/model-id"
import { getProviderOptionsWithOverride } from "@/utils/providers/options"
import { applyTheme } from "@/utils/theme"
import appIcon from "@/assets/icons/opentranslate.png"
import "@/assets/styles/theme.css"
import "./style.css"

enableAppSettingsMode()
setStorageAdapter(createBridgeAdapter())

const resultSchema = z.object({
  translation: z.string(),
  partOfSpeech: z.string().optional(),
  ipa: z.string().optional(),
  alternatives: z.array(z.object({ text: z.string(), note: z.string().optional() })).optional(),
  examples: z.array(z.object({ source: z.string(), target: z.string() })).optional(),
  definitions: z.array(z.string()).optional(),
}).passthrough()
type TranslationResult = z.infer<typeof resultSchema>

// Keep transport replaceable for a future native bridge, while using fetch for direct WKWebView requests.
export type AppTransport = typeof fetch
export const appTransport: AppTransport = (...args) => fetch(...args)
const languageChoices = Object.entries(LANG_CODE_TO_EN_NAME).sort(([, a], [, b]) => a.localeCompare(b))
const fallbackLanguageNames = LANG_CODE_TO_LOCALE_NAME as Record<string, string>
const englishLanguageNames = LANG_CODE_TO_EN_NAME as Record<string, string>
const commonLanguageCodes = ["cmn", "cmn-Hant", "eng", "jpn", "kor", "fra", "deu", "spa", "rus"]

function LanguagePicker({ label, value, includeAuto = false, onChange }: { label: string, value: string, includeAuto?: boolean, onChange: (value: string) => void }) {
  const [open, setOpen] = useState(false)
  const [query, setQuery] = useState("")
  const searchRef = useRef<HTMLInputElement>(null)
  const listRef = useRef<HTMLDivElement>(null)
  const filtered = languageChoices.filter(([code, name]) => `${fallbackLanguageNames[code] ?? name} ${name} ${code}`.toLowerCase().includes(query.trim().toLowerCase()))
  const common = commonLanguageCodes.flatMap(code => filtered.filter(([languageCode]) => languageCode === code))
  const all = filtered.filter(([code]) => !commonLanguageCodes.includes(code))
  const choices = [...(includeAuto && (!query || "自动检测 auto".includes(query.toLowerCase())) ? [["auto", "自动检测"] as [string, string]] : []), ...common, ...all]
  function choose(code: string) {
    onChange(code)
    setOpen(false)
    setQuery("")
  }
  function moveFocus(direction: number) {
    const buttons = [...(listRef.current?.querySelectorAll<HTMLButtonElement>("button") ?? [])]
    const index = buttons.indexOf(document.activeElement as HTMLButtonElement)
    buttons[Math.max(0, Math.min(buttons.length - 1, index + direction))]?.focus()
  }
  return (
    <div className="language-picker">
      <button
        type="button"
        className="language-trigger"
        aria-label={label}
        aria-expanded={open}
        onClick={() => {
          setOpen(!open)
          setQuery("")
          if (!open)
            requestAnimationFrame(() => searchRef.current?.focus())
        }}
      >
        {value === "auto" ? "自动检测" : fallbackLanguageNames[value] ?? englishLanguageNames[value] ?? value}
        <span aria-hidden="true">⌄</span>
      </button>
      {open && (
        <div className="language-popover" role="dialog" aria-label={`${label}选择`}>
          <input
            ref={searchRef}
            className="language-search"
            aria-label="搜索语言"
            placeholder="搜索语言或代码"
            value={query}
            onChange={event => setQuery(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === "Escape") {
                event.preventDefault()
                setOpen(false)
              }
              if (event.key === "ArrowDown") {
                event.preventDefault()
                moveFocus(1)
              }
              if (event.key === "Enter") {
                event.preventDefault()
                if (choices.length)
                  choose(choices[0][0])
              }
            }}
          />
          <div
            ref={listRef}
            className="language-options"
            onKeyDown={(event) => {
              if (event.key === "Escape") {
                event.preventDefault()
                setOpen(false)
              }
              if (event.key === "ArrowDown" || event.key === "ArrowUp") {
                event.preventDefault()
                moveFocus(event.key === "ArrowDown" ? 1 : -1)
              }
            }}
          >
            {includeAuto && choices[0]?.[0] === "auto" && (
              <>
                <div className="language-group">自动检测</div>
                <button type="button" onClick={() => choose("auto")}>自动检测</button>
              </>
            )}
            {common.length > 0 && (
              <>
                <div className="language-group">常用语言</div>
                {common.map(([code, name]) => (
                  <button type="button" key={code} aria-selected={value === code} onClick={() => choose(code)}>
                    {fallbackLanguageNames[code] ?? name}
                    <small>{code}</small>
                  </button>
                ))}
              </>
            )}
            {all.length > 0 && (
              <>
                <div className="language-group">全部语言</div>
                {all.map(([code, name]) => (
                  <button type="button" key={code} aria-selected={value === code} onClick={() => choose(code)}>
                    {fallbackLanguageNames[code] ?? name}
                    <small>{code}</small>
                  </button>
                ))}
              </>
            )}
            {!choices.length && <p className="language-empty">没有匹配的语言</p>}
          </div>
        </div>
      )}
    </div>
  )
}

function parseStructuredResult(raw: string): TranslationResult {
  const candidate = raw.match(/\{[\s\S]*\}/)?.[0]
  if (!candidate)
    return { translation: raw.trim() }
  try {
    const parsed: unknown = JSON.parse(candidate)
    const validated = resultSchema.safeParse(parsed)
    return validated.success ? validated.data : { translation: raw.trim() }
  }
  catch {
    return { translation: raw.trim() }
  }
}

async function requestStructuredTranslation(text: string, source: string, target: string, provider: ProviderConfig): Promise<TranslationResult> {
  if (!isLLMProviderConfig(provider))
    throw new Error("结构化词条需要配置兼容的 AI 提供商，请在完整设置中选择 AI provider。")
  if (isAPIProviderConfig(provider) && !provider.apiKey?.trim())
    throw new Error("该提供商尚未填写 API key。请先在完整设置中添加密钥。")
  const targetName = fallbackLanguageNames[target] ?? englishLanguageNames[target] ?? target
  const sourceName = source === "auto" ? "自动检测" : fallbackLanguageNames[source] ?? englishLanguageNames[source] ?? source
  const modelName = resolveModelId(provider.model)
  const model = await getModelById(provider.id, appTransport)
  const providerOptions = getProviderOptionsWithOverride(modelName ?? "", provider.provider, provider.providerOptions)
  const prompt = `Translate the following text into ${targetName}. Source language: ${sourceName}. Return ONLY valid JSON matching this shape: {"translation":"...","partOfSpeech":"... or empty","ipa":"... or empty","alternatives":[{"text":"...","note":"usage context"}],"examples":[{"source":"...","target":"..."}],"definitions":["..."]}. For normal sentences, partOfSpeech, ipa, and definitions may be omitted. For a single word, provide useful POS/IPA if known. Provide 2-5 alternatives and 2-3 examples when appropriate. Do not invent uncertain IPA. Input:\n${text}`
  let timeoutId: number | undefined
  try {
    const response = await Promise.race([
      generateText({ model, system: "You are a careful bilingual dictionary and translator. Return only the requested JSON object.", prompt, temperature: provider.temperature, providerOptions, maxRetries: 0 }),
      new Promise<never>((_, reject) => {
        timeoutId = window.setTimeout(() => reject(new Error("翻译请求超时，请检查网络后重试。")), 45000)
      }),
    ])
    return parseStructuredResult(response.text)
  }
  finally {
    if (timeoutId !== undefined)
      window.clearTimeout(timeoutId)
  }
}

function TranslateApp() {
  const [config, setConfig] = useState<Config>(DEFAULT_CONFIG)
  const [theme, setTheme] = useState<ThemeMode>("system")
  const [source, setSource] = useState("auto")
  const [target, setTarget] = useState("cmn")
  const [input, setInput] = useState("")
  const [result, setResult] = useState<TranslationResult | null>(null)
  const [error, setError] = useState("")
  const [busy, setBusy] = useState(false)
  const [editing, setEditing] = useState(false)
  const [settings, setSettings] = useState(false)
  const [highlightProvider, setHighlightProvider] = useState(false)
  const [toast, setToast] = useState("")
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const selectedProvider = config.providersConfig.find(item => item.id === config.translate.providerId)
  const usableProviders = useMemo(() => config.providersConfig.filter(item => item.enabled && isTranslateProviderConfig(item) && isLLMProviderConfig(item)), [config.providersConfig])
  const hasKey = Boolean(selectedProvider && isLLMProviderConfig(selectedProvider) && (!isAPIProviderConfig(selectedProvider) || selectedProvider.apiKey?.trim()))

  useEffect(() => {
    void Promise.all([
      storageAdapter.get(CONFIG_STORAGE_KEY, DEFAULT_CONFIG, configSchema),
      storageAdapter.get(THEME_STORAGE_KEY, "system" as ThemeMode, z.enum(["system", "light", "dark"])),
    ]).then(([savedConfig, savedTheme]) => {
      setConfig(savedConfig)
      setSource(savedConfig.language.sourceCode)
      setTarget("cmn")
      setTheme(savedTheme)
    })
  }, [])

  useEffect(() => {
    const update = () => {
      const resolved = theme === "system" ? (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light") : theme
      applyTheme(document.documentElement, resolved)
    }
    update()
    const media = matchMedia("(prefers-color-scheme: dark)")
    media.addEventListener("change", update)
    return () => media.removeEventListener("change", update)
  }, [theme])

  useEffect(() => {
    if (editing)
      textareaRef.current?.focus()
  }, [editing])

  useEffect(() => {
    if (!toast)
      return
    const timer = window.setTimeout(setToast, 2600, "")
    return () => window.clearTimeout(timer)
  }, [toast])

  async function saveConfig(next: Config) {
    setConfig(next)
    await storageAdapter.set(CONFIG_STORAGE_KEY, next, configSchema)
  }

  async function translate(text = input) {
    const normalized = text.trim()
    if (!normalized || busy)
      return
    if (!hasKey || !selectedProvider) {
      setError("添加 AI 提供商及 API key 后即可翻译。")
      setSettings(true)
      setHighlightProvider(true)
      return
    }
    setBusy(true)
    setError("")
    setResult(null)
    try {
      setResult(await requestStructuredTranslation(normalized, source, target, selectedProvider))
    }
    catch (cause) {
      setError(cause instanceof Error ? cause.message : String(cause))
    }
    finally {
      setBusy(false)
    }
  }

  async function updateLanguage(nextSource: string, nextTarget: string) {
    setSource(nextSource)
    setTarget(nextTarget)
    await saveConfig({ ...config, language: { ...config.language, sourceCode: nextSource as Config["language"]["sourceCode"], targetCode: nextTarget as Config["language"]["targetCode"] } })
  }

  async function chooseProvider(id: string) {
    await saveConfig({ ...config, translate: { ...config.translate, providerId: id } })
    setHighlightProvider(false)
  }

  function speak(text: string) {
    if (!("speechSynthesis" in window))
      return
    window.speechSynthesis.cancel()
    window.speechSynthesis.speak(new SpeechSynthesisUtterance(text))
  }

  async function copy(text: string) {
    try {
      await navigator.clipboard.writeText(text)
      setToast("已复制")
    }
    catch {
      setToast("无法访问剪贴板")
    }
  }

  const optionsURL = new URL("../options.html", window.location.href).href
  const translation = result?.translation?.trim()

  return (
    <main className="translate-app">
      {editing
        ? (
            <section className="editor-screen">
              <nav className="editor-nav">
                <button onClick={() => setEditing(false)}>取消</button>
                <strong>输入文字</strong>
                <button
                  className="text-action"
                  onClick={() => {
                    setEditing(false)
                    setResult(null)
                    void translate(input)
                  }}
                >
                  完成
                </button>
              </nav>
              <textarea ref={textareaRef} aria-label="翻译文字" placeholder="输入要翻译的文字" value={input} onChange={event => setInput(event.target.value)} />
              <div className="word-count">
                {input.length}
                {" "}
                字
              </div>
            </section>
          )
        : (
            <>
              <header className="topbar">
                <img src={appIcon} alt="" />
                <strong>OpenTranslate</strong>
                <button className="icon-button" aria-label="设置" onClick={() => setSettings(true)}>⚙</button>
              </header>
              {!hasKey && (
                <button
                  className="setup-banner"
                  onClick={() => {
                    setSettings(true)
                    setHighlightProvider(true)
                  }}
                >
                  添加 AI 提供商后即可翻译
                  <span>设置 →</span>
                </button>
              )}
              <section className="language-bar" aria-label="翻译语言">
                <LanguagePicker label="源语言" value={source} includeAuto onChange={next => void updateLanguage(next, target)} />
                <button
                  className="swap icon-button"
                  aria-label="交换语言"
                  onClick={() => {
                    if (source !== "auto") {
                      void updateLanguage(target, source)
                    }
                    else {
                      setToast("自动检测语言不能交换")
                    }
                  }}
                >
                  ⇄
                </button>
                <LanguagePicker label="目标语言" value={target} onChange={next => void updateLanguage(source, next)} />
              </section>
              <button className="input-card glass" onClick={() => setEditing(true)} aria-label="输入要翻译的文字">
                {input ? <span className="input-content">{input}</span> : <span className="placeholder">翻译文字</span>}
                {input && <span className="edit-hint">点击编辑</span>}
              </button>
              <section className="actions">
                <button className="translate-button" disabled={busy || !input.trim()} onClick={() => void translate()}>
                  {busy
                    ? (
                        <>
                          <span className="spinner" />
                          翻译中…
                        </>
                      )
                    : "翻译"}
                </button>
                <button
                  className="secondary-action"
                  onClick={() => {
                    const SpeechRecognition = (window as Window & { webkitSpeechRecognition?: new () => { start: () => void, onresult: (event: { results: ArrayLike<ArrayLike<{ transcript: string }>> }) => void, onerror: () => void } }).webkitSpeechRecognition
                    if (!SpeechRecognition) {
                      setToast("语音输入将在 App 内启用")
                      return
                    }
                    const recognition = new SpeechRecognition()
                    recognition.onresult = event => setInput(event.results[0][0].transcript)
                    recognition.onerror = () => setToast("语音输入将在 App 内启用")
                    try {
                      recognition.start()
                    }
                    catch { setToast("语音输入将在 App 内启用") }
                  }}
                >
                  <svg aria-hidden="true" viewBox="0 0 24 24">
                    <rect x="9" y="3" width="6" height="12" rx="3" />
                    <path d="M5 11a7 7 0 0 0 14 0M12 18v3m-4 0h8" />
                  </svg>
                  <span>语音</span>
                </button>
                <button className="secondary-action" onClick={() => setToast("拍照翻译将在 App 内启用")}>
                  <svg aria-hidden="true" viewBox="0 0 24 24">
                    <path d="M4 7h3l1.5-2h7L17 7h3a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V8a1 1 0 0 1 1-1Z" />
                    <circle cx="12" cy="13" r="3.5" />
                  </svg>
                  <span>相机</span>
                </button>
              </section>
              {error && <p className="error-message" role="alert">{error}</p>}
              {result && (
                <section className="result-list" aria-live="polite">
                  <article className="result-card glass">
                    <div className="section-label">原文</div>
                    <p>{input}</p>
                    <div className="result-actions">
                      <button onClick={() => void copy(input)}>复制</button>
                      {"speechSynthesis" in window && <button onClick={() => speak(input)}>朗读</button>}
                    </div>
                  </article>
                  {translation && (
                    <article className="result-card glass">
                      <div className="section-label">译文</div>
                      <p className="translated-text">{translation}</p>
                      <div className="result-actions">
                        <button onClick={() => void copy(translation)}>复制</button>
                        {"speechSynthesis" in window && <button onClick={() => speak(translation)}>朗读</button>}
                      </div>
                      {(result.partOfSpeech || result.ipa || result.definitions?.length) && (
                        <div className="ai-definition">
                          <span className="section-label">AI 释义</span>
                          {result.partOfSpeech && <p>{result.partOfSpeech}</p>}
                          {result.ipa && <p className="ipa">{result.ipa}</p>}
                          {result.definitions?.map(item => <p key={item}>{item}</p>)}
                        </div>
                      )}
                      {!!result.alternatives?.length && (
                        <div className="result-subsection">
                          <h3>其他译法</h3>
                          {result.alternatives.slice(0, 5).map((item, index) => (
                            <div className="alternative" key={`${item.text}-${item.note ?? ""}-${index}`}>
                              <strong>{item.text}</strong>
                              {item.note && <span>{item.note}</span>}
                            </div>
                          ))}
                        </div>
                      )}
                      {!!result.examples?.length && (
                        <div className="result-subsection">
                          <h3>例句</h3>
                          {result.examples.slice(0, 3).map((item, index) => (
                            <div className="example" key={`${item.source}-${item.target}-${index}`}>
                              <p>{item.source}</p>
                              <p>{item.target}</p>
                            </div>
                          ))}
                        </div>
                      )}
                    </article>
                  )}
                  <footer className="disclaimer">
                    由
                    {selectedProvider?.name ?? "AI 提供商"}
                    {" "}
                    生成 · AI 结果仅供参考
                  </footer>
                </section>
              )}
            </>
          )}
      {toast && <div className="toast" role="status">{toast}</div>}
      {settings && (
        <div className="sheet-backdrop" onClick={() => setSettings(false)}>
          <section className="settings-sheet glass" role="dialog" aria-modal="true" aria-label="设置" onClick={event => event.stopPropagation()}>
            <div className="sheet-grabber" />
            <header>
              <h2>设置</h2>
              <button className="icon-button" aria-label="关闭设置" onClick={() => setSettings(false)}>×</button>
            </header>
            <label className={highlightProvider ? "highlight" : ""}>
              翻译提供商
              <select value={config.translate.providerId} onChange={event => void chooseProvider(event.target.value)}>
                <option value="">选择提供商</option>
                {usableProviders.map(item => (
                  <option key={item.id} value={item.id}>
                    {item.name}
                    {isAPIProviderConfig(item) && !item.apiKey?.trim() ? "（未配置 key）" : ""}
                  </option>
                ))}
              </select>
            </label>
            <label>
              目标语言
              <select value={target} onChange={event => void updateLanguage(source, event.target.value)}>{languageChoices.map(([code, name]) => <option key={code} value={code}>{fallbackLanguageNames[code] ?? name}</option>)}</select>
            </label>
            <label>
              外观
              <select
                value={theme}
                onChange={(event) => {
                  const mode = event.target.value as ThemeMode
                  setTheme(mode)
                  void storageAdapter.set(THEME_STORAGE_KEY, mode, z.enum(["system", "light", "dark"]))
                }}
              >
                <option value="system">跟随系统</option>
                <option value="light">浅色</option>
                <option value="dark">深色</option>
              </select>
            </label>
            <a className="full-settings" href={optionsURL}>完整设置 →</a>
          </section>
        </div>
      )}
    </main>
  )
}

createRoot(document.getElementById("root")!).render(<TranslateApp />)
