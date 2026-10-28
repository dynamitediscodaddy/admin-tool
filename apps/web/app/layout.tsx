import type { Metadata } from "next";
import "./globals.css";
export const metadata: Metadata = {
  title: "Payments · Admin tool",
  description: "Monthly cash flow across your bank accounts",
};
export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
