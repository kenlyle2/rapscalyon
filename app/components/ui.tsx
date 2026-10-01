import type { ReactNode } from "react";

export function Card({ title, children }: { title?: string; children: ReactNode }) {
  return (
    <section style={{ border: "1px solid #ddd", borderRadius: 8, padding: 16, marginBottom: 16 }}>
      {title && <h2 style={{ marginTop: 0, fontSize: 18 }}>{title}</h2>}
      {children}
    </section>
  );
}

export function Field({ label, children }: { label: string; children: ReactNode }) {
  return (<label style={{ display: "grid", gap: 4, fontSize: 14 }}>{label}{children}</label>);
}

export const formStyle = { display: "grid", gap: 8, maxWidth: 420 } as const;
export const rowStyle = { display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" } as const;
