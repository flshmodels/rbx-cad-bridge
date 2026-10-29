// Inserted into the existing CAD's Babel/React script by prepare-cad-update.cjs.
// It displays imported data; no action here sends a command to Roblox.
function RobloxFeed({ session, allowed }) {
    const [snapshot, setSnapshot] = React.useState(null);
    const [message, setMessage] = React.useState('Connecting to Roblox feed...');
    React.useEffect(() => {
        let cancelled = false, pending = false;
        setSnapshot(null);
        if (!allowed || !session) { setMessage('Select an authorized session to view Roblox data.'); return; }
        const ipc = window.electron?.ipcRenderer;
        if (!ipc) { setMessage('The Roblox feed requires the Electron CAD.'); return; }
        const poll = async () => {
            if (pending) return;
            pending = true;
            try {
                const data = await ipc.invoke('cad-bridge:snapshot');
                if (cancelled || data.session !== session) return;
                setSnapshot(data);
                setMessage('Updated ' + new Date(data.updatedAt).toLocaleTimeString());
            } catch (_) {
                if (!cancelled) {
                    setSnapshot(null);
                    setMessage('Roblox feed unavailable. Check the local bridge config and relay connection.');
                }
            } finally { pending = false; }
        };
        poll();
        const timer = setInterval(poll, 5000);
        return () => { cancelled = true; clearInterval(timer); };
    }, [session, allowed]);
    const card = { background: '#101a27', border: '1px solid #30445d', borderRadius: '8px', padding: '14px', margin: '10px 0' };
    return <section aria-label="Roblox game feed" style={{ ...card, marginBottom: '20px', color: '#e2e8f0' }}>
        <h2 style={{ margin: '0 0 6px', fontSize: '17px' }}>Roblox game feed</h2>
        <p role="status" style={{ color: '#94a3b8', fontSize: '12px' }}>{message}</p>
        {allowed && snapshot?.session === session && Object.entries(snapshot.servers).map(([serverId, data]) => <div key={serverId}>
            <p style={{ color: '#94a3b8', fontSize: '11px', overflowWrap: 'anywhere' }}>Game server: {serverId}</p>
            {Object.entries(data.panics).map(([id, panic]) => <div key={'panic-' + id} style={{ ...card, borderColor: '#f87171' }}>
                <strong>Panic: {panic.callsign || panic.username}</strong><p>{panic.location}</p>
            </div>)}
            <h3 style={{ fontSize: '14px' }}>911 calls ({Object.keys(data.calls).length})</h3>
            {Object.entries(data.calls).map(([id, call]) => <article key={id} style={card}>
                <strong>{call.nature}</strong><p>{call.description}</p><p>{call.location}</p>
                <small>{call.priority} · Caller: {call.callerName} · {new Date(call.createdAt).toLocaleTimeString()}</small>
            </article>)}
            <h3 style={{ fontSize: '14px' }}>Game units ({Object.values(data.units).filter(unit => unit.status !== 'offline').length} online)</h3>
            {Object.entries(data.units).map(([id, unit]) => <p key={id}>
                {unit.callsign || unit.username} · {unit.status} <small style={{ color: '#94a3b8' }}>({unit.username})</small>
            </p>)}
        </div>)}
        {allowed && snapshot?.session === session && !Object.keys(snapshot.servers).length && <p>No Roblox game data has arrived for this session yet.</p>}
    </section>;
}
