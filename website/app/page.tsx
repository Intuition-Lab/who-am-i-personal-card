"use client";

import { useEffect, useMemo, useState } from "react";

const REPOSITORY = "Intuition-Lab/who-am-i-personal-card";
const RELEASES_URL = `https://github.com/${REPOSITORY}/releases`;
const API_URL = `https://api.github.com/repos/${REPOSITORY}/releases?per_page=10`;
const SAFE_DOWNLOAD_PREFIX = `${RELEASES_URL}/download/`;

type ReleaseAsset = {
  name: string;
  browser_download_url: string;
  size: number;
  download_count: number;
  state: string;
};

type GithubRelease = {
  name: string | null;
  tag_name: string;
  html_url: string;
  published_at: string | null;
  prerelease: boolean;
  draft: boolean;
  immutable: boolean;
  assets: ReleaseAsset[];
};

type ReleaseState =
  | { status: "loading"; release: null }
  | { status: "ready"; release: GithubRelease | null }
  | { status: "error"; release: null };

const SAFE_TAG = /^v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/;

function expectedAssets(tag: string) {
  const version = tag.slice(1);
  const packageName = `who-am-i-${version}-self-contained-macos`;
  return [
    `${packageName}.dmg`,
    `${packageName}.tar.gz`,
    "RELEASE-METADATA.txt",
    "RELEASE-NOTES.md",
    "SHA256SUMS",
  ];
}

function approvedRelease(release: GithubRelease) {
  if (release.draft || release.immutable !== true || !SAFE_TAG.test(release.tag_name)) {
    return false;
  }
  const expected = expectedAssets(release.tag_name);
  const actual = release.assets.map((asset) => asset.name);
  if (new Set(actual).size !== expected.length || actual.length !== expected.length) {
    return false;
  }
  if (!expected.every((name) => actual.includes(name))) return false;
  return release.assets.every((asset) =>
    asset.state === "uploaded" &&
    Number.isFinite(asset.size) &&
    asset.size > 0 &&
    asset.browser_download_url ===
      `${SAFE_DOWNLOAD_PREFIX}${release.tag_name}/${asset.name}`
  );
}

function safeAsset(release: GithubRelease | null, name: string) {
  const asset = release?.assets.find((candidate) => candidate.name === name);
  if (!asset || !release || !approvedRelease(release)) return null;
  return asset;
}

function formatBytes(bytes: number) {
  if (!Number.isFinite(bytes) || bytes <= 0) return "";
  const megabytes = bytes / (1024 * 1024);
  return `${megabytes >= 100 ? Math.round(megabytes) : megabytes.toFixed(1)} MB`;
}

function formatDate(value: string | null) {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return new Intl.DateTimeFormat("zh-CN", {
    year: "numeric",
    month: "long",
    day: "numeric",
  }).format(date);
}

export default function Home() {
  const [releaseState, setReleaseState] = useState<ReleaseState>({
    status: "loading",
    release: null,
  });

  useEffect(() => {
    const controller = new AbortController();
    const loadRelease = async () => {
      try {
        const response = await fetch(API_URL, {
          headers: { Accept: "application/vnd.github+json" },
          cache: "no-store",
          signal: controller.signal,
        });
        if (!response.ok) throw new Error("GitHub release request failed");
        const releases = (await response.json()) as GithubRelease[];
        const release = releases.find(approvedRelease) ?? null;
        setReleaseState({ status: "ready", release });
      } catch (error) {
        if ((error as Error).name !== "AbortError") {
          setReleaseState({ status: "error", release: null });
        }
      }
    };
    void loadRelease();
    return () => controller.abort();
  }, []);

  const release = releaseState.release;
  const dmg = useMemo(() => {
    if (!release) return null;
    return safeAsset(release, expectedAssets(release.tag_name)[0]);
  }, [release]);
  const checksum = useMemo(
    () => release?.assets.find((asset) => asset.name === "SHA256SUMS") ?? null,
    [release],
  );
  const releaseUrl =
    release?.html_url.startsWith(`${RELEASES_URL}/tag/`)
      ? release.html_url
      : RELEASES_URL;

  const releaseMessage = (() => {
    if (releaseState.status === "loading") return "正在读取 GitHub Release";
    if (releaseState.status === "error") return "GitHub 状态暂时不可用";
    if (!release) return "首个内测包正在通过发布门禁";
    if (!dmg) return "最新 Release 尚未包含 macOS 安装包";
    return `${release.tag_name}${release.prerelease ? " · 内测版" : " · 正式版"}`;
  })();

  return (
    <main>
      <nav className="nav shell" aria-label="主导航">
        <a className="wordmark" href="#top" aria-label="Who Am I 首页">
          <span className="wordmark-dot" aria-hidden="true" />
          WHO AM I
        </a>
        <a className="repo-link" href={`https://github.com/${REPOSITORY}`}>
          GitHub
          <span aria-hidden="true">↗</span>
        </a>
      </nav>

      <section className="hero shell" id="top">
        <div className="eyebrow">
          <span className="live-dot" aria-hidden="true" />
          SELF-CONTAINED PERSONAL MODEL
        </div>
        <h1>
          你的 Personal Model，
          <span>只属于你。</span>
        </h1>
        <p className="hero-copy">
          一个本地运行的 Mac App。下载一次，自动连接你已有的 Personal Model；
          如果没有，就在这台电脑上为你初始化一个新的。
        </p>

        <div className="release-panel" aria-live="polite">
          <div className="release-main">
            <div>
              <p className="release-label">LATEST RELEASE</p>
              <p className="release-status">{releaseMessage}</p>
            </div>
            {dmg ? (
              <a className="download-button" href={dmg.browser_download_url}>
                下载 Mac App
                <span aria-hidden="true">↓</span>
              </a>
            ) : (
              <a className="download-button secondary" href={RELEASES_URL}>
                查看发布状态
                <span aria-hidden="true">↗</span>
              </a>
            )}
          </div>

          <div className="release-meta">
            <span>{dmg ? formatBytes(dmg.size) : "macOS 13+"}</span>
            <span>Apple Silicon + Intel</span>
            {release?.published_at ? <span>{formatDate(release.published_at)}</span> : null}
            {checksum ? <span>SHA-256 可验证</span> : null}
          </div>
        </div>

        <p className="release-note">
          这个页面直接读取 GitHub Releases。每次新的内测包发布后，下载按钮会自动指向最新版本。
          <a href={releaseUrl}>查看完整 Release</a>
        </p>
      </section>

      <section className="principle shell" aria-label="产品原则">
        <p>NO SHARED CARD</p>
        <p>NO CLOUD PROFILE</p>
        <p>NO SECOND REPOSITORY</p>
      </section>

      <section className="steps shell" aria-labelledby="steps-title">
        <div className="section-heading">
          <p className="section-index">01 — 安装</p>
          <h2 id="steps-title">从下载到你的 Card，只要三步。</h2>
        </div>
        <div className="step-grid">
          <article>
            <span>01</span>
            <h3>下载一个 App</h3>
            <p>从最新 GitHub Release 下载 DMG，打开后双击 Who Am I.app。</p>
          </article>
          <article>
            <span>02</span>
            <h3>连接你的模型</h3>
            <p>已有 Personal Model 会自动复用；没有就从内嵌的锁定版本初始化。</p>
          </article>
          <article>
            <span>03</span>
            <h3>看到你自己的 Card</h3>
            <p>Card、Identity、Rewind、Evidence 和 Report 都只读取当前用户的数据。</p>
          </article>
        </div>
      </section>

      <section className="privacy shell" aria-labelledby="privacy-title">
        <div className="privacy-copy">
          <p className="section-index light">02 — 隐私边界</p>
          <h2 id="privacy-title">下载的是软件，不是任何人的记忆。</h2>
          <p>
            安装包包含产品代码和锁定的 Personal Model Runtime，不包含开发者的 Card、数据库、
            对话、Evidence 或身份资料。每位用户的数据只在自己的 Mac 上创建。
          </p>
        </div>
        <div className="privacy-diagram" aria-label="本地数据流">
          <div>
            <span>THIS MAC</span>
            <strong>Personal Model</strong>
          </div>
          <span className="flow" aria-hidden="true">→</span>
          <div>
            <span>LOCAL APP</span>
            <strong>Your Card</strong>
          </div>
        </div>
      </section>

      <section className="release-truth shell" aria-labelledby="truth-title">
        <div>
          <p className="section-index">03 — 实时发布</p>
          <h2 id="truth-title">GitHub 是唯一发布源。</h2>
        </div>
        <div className="truth-list">
          <p><span>01</span> 固定 Runtime commit 与 tree</p>
          <p><span>02</span> DMG、tar 和校验文件同时发布</p>
          <p><span>03</span> 两种 Mac 架构安装验证后才可发布</p>
          <p><span>04</span> 每个 Release 创建后不可覆盖</p>
        </div>
      </section>

      <footer className="footer shell">
        <div>
          <span className="footer-mark" aria-hidden="true">W</span>
          <p>Who Am I by Intuition Lab</p>
        </div>
        <p>Personal by default. Local by design.</p>
      </footer>
    </main>
  );
}
