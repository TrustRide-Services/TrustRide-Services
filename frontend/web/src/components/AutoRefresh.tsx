"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";

// Re-renders the page's projections every few seconds (live order status,
// tracking, the Operator App's job list).
export default function AutoRefresh({ seconds = 10 }: { seconds?: number }) {
  const router = useRouter();
  useEffect(() => {
    const t = setInterval(() => router.refresh(), seconds * 1000);
    return () => clearInterval(t);
  }, [router, seconds]);
  return null;
}
