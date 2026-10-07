"use client";

import { useEffect, useRef, useState } from "react";
import { reportLocationAction } from "./actions";

// While a job is under way, the operator's phone reports its position every
// 30 seconds (TRACK_ELEMENT on the Operator App). Vehicles fitted with a
// Protrack tracker report on their own; this covers the rest.
export default function LocationShare({ jobId }: { jobId: string }) {
  const [on, setOn] = useState(false);
  const [status, setStatus] = useState("");
  const last = useRef(0);
  useEffect(() => {
    if (!on || !("geolocation" in navigator)) return;
    const id = navigator.geolocation.watchPosition(
      async (pos) => {
        if (Date.now() - last.current < 30000) return;
        last.current = Date.now();
        const r = await reportLocationAction(jobId, pos.coords.latitude, pos.coords.longitude);
        setStatus(r.error ?? `Shared ${new Date().toLocaleTimeString("en-KE")}`);
      },
      (err) => setStatus(err.message),
      { enableHighAccuracy: true, maximumAge: 10000 },
    );
    return () => navigator.geolocation.clearWatch(id);
  }, [on, jobId]);
  return (
    <div className="trs-card p-4 flex flex-wrap items-center gap-3">
      <label className="flex items-center gap-2 text-sm text-text-primary">
        <input type="checkbox" checked={on} onChange={(e) => setOn(e.target.checked)} /> Share my location with the customer during this job
      </label>
      {status && <span className="text-xs text-text-muted">{status}</span>}
    </div>
  );
}
