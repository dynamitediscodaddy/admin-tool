import { NextRequest, NextResponse } from "next/server";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  const baseUrl = process.env.API_BASE_URL ?? "http://localhost:8080";
  const url = new URL("/api/dashboard", baseUrl);
  const year = request.nextUrl.searchParams.get("year");
  if (year !== null) url.searchParams.set("year", year);

  try {
    const response = await fetch(url, {
      cache: "no-store",
      signal: AbortSignal.timeout(10_000),
    });
    return new Response(await response.text(), {
      status: response.status,
      headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
    });
  } catch {
    return NextResponse.json({ error: "Payments API unavailable" }, { status: 502 });
  }
}
