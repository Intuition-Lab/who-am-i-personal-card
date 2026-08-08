import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import { headers } from "next/headers";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export async function generateMetadata(): Promise<Metadata> {
  const requestHeaders = await headers();
  const host = requestHeaders.get("x-forwarded-host") ?? requestHeaders.get("host");
  const forwardedProtocol = requestHeaders.get("x-forwarded-proto");
  const protocol = forwardedProtocol ?? (host?.startsWith("localhost") ? "http" : "https");
  const origin = host ? `${protocol}://${host}` : "https://github.com/Intuition-Lab/who-am-i-personal-card";
  const socialImage = `${origin}/og.png`;

  return {
    title: "Who Am I — 你的 Personal Model，只属于你",
    description:
      "下载自包含的 Who Am I Mac App，连接或初始化你自己的 Personal Model 与 Personal Card。",
    openGraph: {
      title: "Who Am I — Personal by default",
      description: "一个本地运行、只显示你自己数据的 Personal Model Mac App。",
      type: "website",
      images: [{ url: socialImage, width: 1200, height: 630 }],
    },
    twitter: {
      card: "summary_large_image",
      title: "Who Am I — Personal by default",
      description: "一个本地运行、只显示你自己数据的 Personal Model Mac App。",
      images: [socialImage],
    },
  };
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="zh-CN">
      <body className={`${geistSans.variable} ${geistMono.variable}`}>
        {children}
      </body>
    </html>
  );
}
