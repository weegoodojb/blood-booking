"use client";
import { Slot } from "@/lib/supabase";
export default function Slots({slots, selected, onSelect}:{slots:Slot[];selected:string;onSelect:(id:string)=>void}) { return <div>{slots.map(s=>{const closed=!s.enabled||s.booked>=s.capacity; return <button type="button" key={s.id} disabled={closed} onClick={()=>onSelect(s.id)} className={`slot ${selected===s.id?'selected':''} ${closed?'closed':''}`}><b>{s.slot_time.slice(0,5)}</b><span>{s.booked} / {s.capacity}명 {closed && <strong style={{marginLeft:8}}>마감</strong>}</span></button>})}</div> }
