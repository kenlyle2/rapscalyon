import Link from "next/link";
import { catalog } from "@/lib/packs/catalog.generated";

export const metadata = { title: "Packs" };

export default function Packs() {
  return (
    <main style={{ maxWidth: 960, margin: "0 auto", padding: "32px 16px" }}>
      <h1>Packs</h1>
      <p>Install only what your product needs. Every pack is tested, row-level-secured and removable.</p>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(260px, 1fr))", gap: 16 }}>
        {catalog.map((p) => (
          <Link key={p.name} href={`/packs/${p.name}`} style={{ border: "1px solid #ddd", borderRadius: 8, padding: 16, textDecoration: "none", color: "inherit" }}>
            <h2 style={{ marginTop: 0, fontSize: 18 }}>{p.title}</h2>
            <p>{p.tagline}</p>
            <small>{p.tier} · v{p.version}</small>
          </Link>
        ))}
      </div>
    </main>
  );
}
