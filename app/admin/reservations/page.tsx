"use client";
import { useEffect, useState } from "react";
import { Header } from "@/components/Header";
import { supabase } from "@/lib/supabase";

type Reservation = { id:string; name:string; phone:string; participant_type?:string; employee_id?:string; workplace?:string; reservation_status:string; donation_status:string };
type Slot = { id:string; slot_time:string; capacity:number; enabled:boolean; reservations:Reservation[] };

function statusOf(row:Reservation){
 if(row.donation_status==='completed') return ['헌혈완료','complete'];
 if(row.donation_status==='ineligible') return ['헌혈불가','ineligible'];
 if(row.reservation_status==='no_show') return ['미참석','noshow'];
 if(row.reservation_status==='checked_in') return ['참석','checked'];
 return ['예약','reserved'];
}

export default function ReservationsPage(){
 const [slots,setSlots]=useState<Slot[]>([]),[message,setMessage]=useState('');
 const load=async()=>{
  setMessage('');
  const {data:event,error:eventError}=await supabase.from('events').select('id').eq('active',true).order('event_date',{ascending:false}).limit(1).maybeSingle();
  if(eventError){setMessage(`행사 정보를 불러오지 못했습니다: ${eventError.message}`);return}
  if(!event){setSlots([]);setMessage('활성화된 행사가 없습니다.');return}
  const {data,error}=await supabase.from('time_slots').select('id,slot_time,capacity,enabled,reservations(id,name,phone,participant_type,employee_id,workplace,reservation_status,donation_status)').eq('event_id',event.id).order('slot_time');
  if(error){setMessage(`예약 현황을 불러오지 못했습니다: ${error.message}`);return}
  setSlots((data||[]) as Slot[]);
 };
 useEffect(()=>{load()},[]);
 const activeSlots=slots.filter(slot=>slot.enabled);
 const totalBooked=activeSlots.reduce((sum,slot)=>sum+slot.reservations.filter(r=>r.reservation_status!=='cancelled').length,0);
 const totalCapacity=activeSlots.reduce((sum,slot)=>sum+slot.capacity,0);
 return <main className="page admin"><Header/><a href="/admin" style={{color:'#1e4fa3'}}>← 관리자 메뉴</a><div style={{display:'flex',justifyContent:'space-between',alignItems:'baseline',gap:12,flexWrap:'wrap'}}><h1>예약 현황</h1><a href="/admin/lookup" className="small-btn" style={{textDecoration:'none'}}>예약자 조회·처리</a></div><p className="hint">시간대별 예약자와 진행 상태를 한눈에 확인합니다. <b>예약자 이름을 누르면 해당 예약자만 처리합니다.</b></p><div className="admin-grid" style={{marginBottom:14}}><div className="stat"><span className="hint">전체 예약</span><b style={{display:'block',fontSize:'1.25rem',marginTop:7}}>{totalBooked}/{totalCapacity}명</b></div><div className="stat"><span className="hint">시간대</span><b style={{display:'block',fontSize:'1.25rem',marginTop:7}}>{activeSlots.length}개</b></div></div><div className="status-legend"><span className="badge reserved">예약</span><span className="badge checked">참석</span><span className="badge complete">헌혈완료</span><span className="badge ineligible">헌혈불가</span><span className="badge noshow">미참석</span></div>{message&&<p style={{color:message.includes('못')?'#bd293b':'#687386'}}>{message}</p>}{slots.map(slot=>{const booked=slot.reservations.filter(r=>r.reservation_status!=='cancelled');return <section className={`card slot-overview ${slot.enabled?'':'slot-disabled'}`} key={slot.id}><div className="slot-overview-head"><div><b>{slot.slot_time.slice(0,5)}</b><span className="hint"> · {slot.enabled?`${booked.length}/${slot.capacity}명 예약`:'예약 불가 시간'}</span></div><span className={slot.enabled&&booked.length>=slot.capacity?'badge full':'badge reserved'}>{slot.enabled&&booked.length>=slot.capacity?'마감':slot.enabled?'접수 중':'예약 불가'}</span></div>{slot.enabled&&booked.length===0&&<p className="hint" style={{margin:'12px 0 0'}}>예약자가 없습니다.</p>}{booked.map(row=>{const [label,kind]=statusOf(row);return <article key={row.id} className={`participant ${kind}`}><div><a href={`/admin/lookup?reservationId=${encodeURIComponent(row.id)}`} style={{color:'#1e4fa3',fontWeight:700,textDecoration:'underline'}}>{row.name}</a>{row.participant_type==='employee'&&<span className="hint"> · {row.workplace||'근무처 미입력'}</span>}<div className="hint"><a href={`tel:${row.phone}`}>{row.phone}</a>{row.employee_id?` · 사번 ${row.employee_id}`:''}</div></div><span className={`badge ${kind}`}>{label}</span></article>})}</section>})}</main>;
}
