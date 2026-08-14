"use client";

import Image from "next/image";
import { useEffect, useState } from "react";
import { Contacts, Header } from "@/components/Header";
import Slots from "@/components/Slots";
import { EventInfo, phoneOnly, Slot, supabase } from "@/lib/supabase";

type Contact = { label: string; phone: string };

export default function Home() {
  const [event, setEvent] = useState<EventInfo | null>(null);
  const [slots, setSlots] = useState<Slot[]>([]);
  const [contacts, setContacts] = useState<Contact[]>([]);
  const [slot, setSlot] = useState("");
  const [message, setMessage] = useState("");
  const [loadError, setLoadError] = useState("");
  const [loading, setLoading] = useState(false);
  const [form, setForm] = useState({ name: "", phone: "", pin: "", employeeId: "", workplace: "", privacy: false });

  const loadBookingData = async () => {
    setLoadError("");
    const { data, error } = await supabase.rpc("public_booking_data");
    const row = data?.[0];
    if (error) return setLoadError(`예약 정보를 불러오지 못했습니다: ${error.message}`);
    if (!row?.event) return setLoadError("현재 예약 가능한 헌혈행사가 없습니다. 담당자에게 문의해주세요.");
    setEvent(row.event);
    setSlots(row.slots || []);
    setContacts(row.contacts || []);
  };

  useEffect(() => { loadBookingData(); }, []);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setMessage("");
    if (!/^\d{4}$/.test(form.pin)) return setMessage("예약 PIN은 숫자 4자리로 입력해주세요.");
    if (!form.employeeId.trim()) return setMessage("사번을 입력해주세요.");
    if (!form.workplace.trim()) return setMessage("근무처를 입력해주세요.");
    if (!slot || !form.privacy) return setMessage("개인정보 동의와 예약 시간을 확인해주세요.");
    setLoading(true);
    const { data, error } = await supabase.rpc("create_reservation", {
      p_event_id: event!.id, p_slot_id: slot, p_name: form.name.trim(), p_phone: phoneOnly(form.phone), p_pin: form.pin,
      p_eligibility_checked: false, p_participant_type: "employee", p_employee_id: form.employeeId.trim(),
      p_work_area_type: null, p_ward: null, p_workplace: form.workplace.trim(),
    });
    setLoading(false);
    if (error || !data?.ok) return setMessage(data?.message || "예약 처리 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.");
    sessionStorage.setItem("booking_complete", JSON.stringify(data.reservation));
    location.href = "/complete";
  };

  if (!event) return <main className="page"><Header />{loadError ? <><p style={{ color: "#bd293b" }}>{loadError}</p><button className="btn btn-outline" onClick={loadBookingData}>다시 시도</button></> : <p className="hint">예약 정보를 불러오는 중입니다.</p>}</main>;
  return <main className="page">
    <Header />
    <h1 style={{ fontSize: "1.55rem" }}>헌혈예약</h1>
    <p className="hint">{event.title}<br /><b>헌혈행사일: {event.event_date}</b>{event.location && <> · {event.location}</>}</p>
    <form onSubmit={submit}>
      <label className="label">이름</label><input required value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} />
      <label className="label">전화번호</label><input required inputMode="numeric" value={form.phone} onChange={e => setForm({ ...form, phone: phoneOnly(e.target.value) })} placeholder="- 없이 숫자만 입력해주세요" />
      <label className="label">사번</label><input required value={form.employeeId} onChange={e => setForm({ ...form, employeeId: e.target.value })} placeholder="사번을 입력해주세요" />
      <label className="label">근무처</label><input required value={form.workplace} onChange={e => setForm({ ...form, workplace: e.target.value })} placeholder="예: 외래진료과, 행정팀, 보안팀, 71병동" />
      <label className="label">예약 PIN (숫자 4자리)</label><input required inputMode="numeric" maxLength={4} value={form.pin} onChange={e => setForm({ ...form, pin: phoneOnly(e.target.value).slice(0, 4) })} />
      <section style={{ margin: "20px 0" }} aria-label="헌혈 가능 간이 안내"><Image src="/donation-eligibility-guide.png" alt="헌혈 가능 간이 안내" width={2048} height={1536} priority style={{ width: "100%", height: "auto", borderRadius: 10, display: "block" }} /></section>
      {event.questionnaire_url && <div style={{ marginBottom: 16 }}><a target="_blank" href={event.questionnaire_url} style={{ color: "#1e4fa3", fontSize: "1.15rem", fontWeight: 700 }}>전자문진 사이트 ↗</a></div>}
      <label className="label" style={{ display: "flex", gap: 9, alignItems: "start", fontWeight: 400 }}><input type="checkbox" style={{ width: 18, marginTop: 2 }} checked={form.privacy} onChange={e => setForm({ ...form, privacy: e.target.checked })} /><span>개인정보 수집·이용에 동의합니다. <b style={{ color: "#cc3344" }}>(필수)</b><br />개인정보제공에 동의하지 않으시면 현장방문 바랍니다.</span></label>
      <p className="hint">수집 항목: 이름, 전화번호, 사번, 근무처<br />이용 목적: {event.privacy_purpose}<br />보관기간: {event.privacy_retention}<br />파기 시점: {event.privacy_disposal}</p>
      <h2 style={{ fontSize: "1.1rem", marginTop: 26 }}>예약 시간 선택</h2><Slots slots={slots} selected={slot} onSelect={setSlot} />
      {message && <p style={{ color: "#bd293b" }}>{message}</p>}<button className="btn" disabled={loading} style={{ marginTop: 16 }}>{loading ? "예약 중…" : "예약하기"}</button>
    </form>
    <a href="/reservation" style={{ display: "block", textAlign: "center", color: "#1e4fa3", fontWeight: 700, marginTop: 20 }}>예약 조회 / 수정 / 취소</a>
    <Contacts contacts={contacts} />
  </main>;
}
