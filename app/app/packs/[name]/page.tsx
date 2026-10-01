import Link from "next/link";
import { notFound } from "next/navigation";
import { catalog } from "@/lib/packs/catalog.generated";

export function generateStaticParams() { return catalog.map((p) => ({ name: p.name })); }

export default async function Pack({ params }: { params: Promise<{ name: string }> }) {
  const { name } = await params;
  const p = catalog.find((x) => x.name === name);
  if (!p) notFound();
  return (
    <main style={{ maxWidth: 720, margin: "0 auto", padding: "32px 16px" }}>
      <p><Link href="/packs">← All packs</Link></p>
      <h1>{p.title}</h1>
      <p style={{ fontSize: 20 }}>{p.tagline}</p>
      <p><small>{p.tier} pack · v{p.version} · {p.license}</small></p>
      {Object.entries(p.sections).map(([heading, lines]) => (
        <section key={heading}>
          <h2>{heading}</h2>
          {heading === "What you get" ? <ul>{lines.map((l) => <li key={l}>{l}</li>)}</ul> : lines.map((l) => <p key={l}>{l}</p>)}
        </section>
      ))}
      <p><code>python3 tools/rapscalyon.py pack add packs/{p.name} --app app</code></p>
    </main>
  );
}
