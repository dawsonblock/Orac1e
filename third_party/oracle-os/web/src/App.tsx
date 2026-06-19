import { useEffect, useMemo, useState } from 'react';
import { Activity, Boxes, CircleAlert, ShieldCheck, Wrench } from 'lucide-react';

type ToolRecord = {
  id: string;
  name: string;
  kind: string;
  capabilities: string[];
  base_url: string;
  invoke_path: string;
  health_path: string;
  risk_level: string;
  healthy: boolean | null;
  detail?: string | null;
};

type ToolRegistrySnapshot = {
  generated_at: string;
  root_path: string;
  tool_count: number;
  capabilities: string[];
  tools: ToolRecord[];
};

const fallbackSnapshot: ToolRegistrySnapshot = {
  generated_at: new Date().toISOString(),
  root_path: 'integration/tools',
  tool_count: 3,
  capabilities: [
    'retrieval.code.search',
    'worker.code.interactive',
    'worker.code.issue_fix',
    'worker.code.patch',
  ],
  tools: [
    {
      id: 'cocoindex',
      name: 'Cocoindex Retrieval',
      kind: 'retrieval',
      capabilities: ['retrieval.code.search'],
      base_url: 'http://127.0.0.1:8787',
      invoke_path: '/invoke',
      health_path: '/health',
      risk_level: 'low',
      healthy: null,
      detail: 'Static fallback snapshot. Run bootstrap to sync real manifests.',
    },
    {
      id: 'aider',
      name: 'Aider Worker',
      kind: 'worker',
      capabilities: ['worker.code.patch', 'worker.code.interactive'],
      base_url: 'http://127.0.0.1:8788',
      invoke_path: '/invoke',
      health_path: '/health',
      risk_level: 'medium',
      healthy: null,
      detail: 'Static fallback snapshot. Run bootstrap to sync real manifests.',
    },
    {
      id: 'hardened',
      name: 'Hardened Code Worker',
      kind: 'worker',
      capabilities: ['worker.code.patch', 'worker.code.issue_fix'],
      base_url: 'http://127.0.0.1:8789',
      invoke_path: '/invoke',
      health_path: '/health',
      risk_level: 'medium',
      healthy: null,
      detail: 'Static fallback snapshot. Run bootstrap to sync real manifests.',
    },
  ],
};

function StatCard({ title, value, subtitle, icon }: { title: string; value: string; subtitle: string; icon: React.ReactNode }) {
  return (
    <section className="bg-slate-900 rounded-xl p-5 border border-slate-800 shadow-xl">
      <div className="flex items-center justify-between mb-5">
        <div>
          <div className="text-xs uppercase tracking-wider text-slate-500 font-semibold">{title}</div>
          <div className="text-2xl font-semibold text-white mt-2">{value}</div>
        </div>
        <div className="p-3 rounded-lg bg-slate-800 text-indigo-300">{icon}</div>
      </div>
      <p className="text-sm text-slate-400">{subtitle}</p>
    </section>
  );
}

function statusTone(healthy: boolean | null) {
  if (healthy === true) return 'text-emerald-400 border-emerald-500/30 bg-emerald-500/10';
  if (healthy === false) return 'text-amber-300 border-amber-500/30 bg-amber-500/10';
  return 'text-slate-300 border-slate-600 bg-slate-700/40';
}

function statusLabel(healthy: boolean | null) {
  if (healthy === true) return 'Healthy';
  if (healthy === false) return 'Unreachable';
  return 'Unknown';
}

export default function App() {
  const [snapshot, setSnapshot] = useState<ToolRegistrySnapshot>(fallbackSnapshot);
  const [loadedFromFile, setLoadedFromFile] = useState(false);

  useEffect(() => {
    let active = true;
    fetch('/tool-registry.json', { cache: 'no-store' })
      .then((res) => (res.ok ? res.json() : Promise.reject(new Error(`HTTP ${res.status}`))))
      .then((data: ToolRegistrySnapshot) => {
        if (!active) return;
        setSnapshot(data);
        setLoadedFromFile(true);
      })
      .catch(() => {
        if (!active) return;
        setSnapshot(fallbackSnapshot);
        setLoadedFromFile(false);
      });
    return () => {
      active = false;
    };
  }, []);

  const counts = useMemo(() => {
    let healthy = 0;
    let unhealthy = 0;
    let unknown = 0;
    for (const tool of snapshot.tools) {
      if (tool.healthy === true) healthy += 1;
      else if (tool.healthy === false) unhealthy += 1;
      else unknown += 1;
    }
    return { healthy, unhealthy, unknown };
  }, [snapshot]);

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 p-6 md:p-8">
      <div className="max-w-7xl mx-auto space-y-6">
        <header className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
          <div>
            <div className="flex items-center gap-3 mb-3">
              <div className="p-3 rounded-xl bg-indigo-500/10 border border-indigo-500/20 text-indigo-300">
                <Wrench className="w-6 h-6" />
              </div>
              <div>
                <h1 className="text-3xl font-bold tracking-tight text-white">Oracle Tool Registry</h1>
                <p className="text-slate-400">Manifest-driven discovery surface for workers and retrieval tools.</p>
              </div>
            </div>
            <div className="text-sm text-slate-500">
              Root: <span className="font-mono text-slate-300">{snapshot.root_path}</span>
            </div>
          </div>
          <div className="rounded-xl border border-slate-800 bg-slate-900 px-4 py-3 text-sm text-slate-300">
            <div>{loadedFromFile ? 'Loaded from tool-registry.json' : 'Using fallback snapshot'}</div>
            <div className="text-slate-500 mt-1">Generated: {new Date(snapshot.generated_at).toLocaleString()}</div>
          </div>
        </header>

        <section className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-4">
          <StatCard
            title="Discovered Tools"
            value={String(snapshot.tool_count)}
            subtitle="Total manifests currently visible to the UI snapshot."
            icon={<Boxes className="w-5 h-5" />}
          />
          <StatCard
            title="Healthy"
            value={String(counts.healthy)}
            subtitle="Tools that answered a live health probe when the snapshot was created."
            icon={<ShieldCheck className="w-5 h-5" />}
          />
          <StatCard
            title="Unreachable"
            value={String(counts.unhealthy)}
            subtitle="Tools that had manifests but did not answer their health endpoint."
            icon={<CircleAlert className="w-5 h-5" />}
          />
          <StatCard
            title="Capabilities"
            value={String(snapshot.capabilities.length)}
            subtitle="Unique capability tags advertised across all discovered tools."
            icon={<Activity className="w-5 h-5" />}
          />
        </section>

        <section className="grid grid-cols-1 xl:grid-cols-[2fr_1fr] gap-6">
          <div className="bg-slate-900 rounded-xl border border-slate-800 shadow-xl overflow-hidden">
            <div className="px-5 py-4 border-b border-slate-800 flex items-center justify-between">
              <div>
                <h2 className="font-semibold text-white">Tool List</h2>
                <p className="text-sm text-slate-500">Each tool is represented by one manifest plus one invoke endpoint.</p>
              </div>
            </div>
            <div className="divide-y divide-slate-800">
              {snapshot.tools.map((tool) => (
                <div key={tool.id} className="p-5 space-y-4">
                  <div className="flex flex-col md:flex-row md:items-start md:justify-between gap-3">
                    <div>
                      <div className="text-lg font-semibold text-white">{tool.name}</div>
                      <div className="text-sm text-slate-500 font-mono">{tool.id}</div>
                    </div>
                    <div className={`inline-flex items-center rounded-full px-3 py-1 text-xs font-semibold border ${statusTone(tool.healthy)}`}>
                      {statusLabel(tool.healthy)}
                    </div>
                  </div>
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-3 text-sm">
                    <div className="rounded-lg bg-slate-950/70 border border-slate-800 p-3">
                      <div className="text-slate-500 mb-1">Kind</div>
                      <div className="text-slate-200">{tool.kind}</div>
                    </div>
                    <div className="rounded-lg bg-slate-950/70 border border-slate-800 p-3">
                      <div className="text-slate-500 mb-1">Risk</div>
                      <div className="text-slate-200">{tool.risk_level}</div>
                    </div>
                    <div className="rounded-lg bg-slate-950/70 border border-slate-800 p-3 md:col-span-2">
                      <div className="text-slate-500 mb-1">Base URL</div>
                      <div className="text-slate-200 font-mono break-all">{tool.base_url}</div>
                    </div>
                    <div className="rounded-lg bg-slate-950/70 border border-slate-800 p-3 md:col-span-2">
                      <div className="text-slate-500 mb-2">Capabilities</div>
                      <div className="flex flex-wrap gap-2">
                        {tool.capabilities.map((capability) => (
                          <span key={capability} className="px-2.5 py-1 rounded-full bg-indigo-500/10 text-indigo-200 border border-indigo-500/20 text-xs font-medium">
                            {capability}
                          </span>
                        ))}
                      </div>
                    </div>
                  </div>
                  {tool.detail ? <div className="text-sm text-slate-400">{tool.detail}</div> : null}
                </div>
              ))}
            </div>
          </div>

          <div className="space-y-6">
            <section className="bg-slate-900 rounded-xl border border-slate-800 shadow-xl p-5">
              <h2 className="font-semibold text-white mb-4">Registry Summary</h2>
              <div className="space-y-3 text-sm">
                <div>
                  <div className="text-slate-500 mb-1">Manifest Root</div>
                  <div className="font-mono text-slate-300 break-all">{snapshot.root_path}</div>
                </div>
                <div>
                  <div className="text-slate-500 mb-2">Capability Vocabulary</div>
                  <div className="flex flex-wrap gap-2">
                    {snapshot.capabilities.map((capability) => (
                      <span key={capability} className="px-2.5 py-1 rounded-full bg-slate-800 text-slate-200 border border-slate-700 text-xs font-medium">
                        {capability}
                      </span>
                    ))}
                  </div>
                </div>
              </div>
            </section>

            <section className="bg-slate-900 rounded-xl border border-slate-800 shadow-xl p-5">
              <h2 className="font-semibold text-white mb-4">Extension Rules</h2>
              <ul className="space-y-3 text-sm text-slate-400">
                <li>Every new tool should ship with one manifest and one <span className="font-mono text-slate-300">/invoke</span> endpoint.</li>
                <li>Oracle remains the authority for runs, approvals, validation, and final patch apply.</li>
                <li>Route by capability tags, not by hardcoded tool names.</li>
                <li>Keep adapters thin: translate, invoke, normalize, enforce safety.</li>
              </ul>
            </section>
          </div>
        </section>
      </div>
    </div>
  );
}
