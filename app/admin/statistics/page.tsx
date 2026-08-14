"use client";

import { useEffect, useState } from "react";
import { Header } from "@/components/Header";
import { supabase } from "@/lib/supabase";

const summaryCards = [
  ["available", "현재 예약 가능한 인원"], ["reserved", "예약 인원"], ["cancelled", "취소"],
  ["no_show", "미참석"], ["completed", "헌혈완료"], ["ineligible", "헌혈불가"],
  ["walkins", "비예약 인원"], ["reservation_completed", "예약 헌혈완료"], ["walkin_completed", "비예약 헌혈완료"],
] as const;

const detailTitles: Record<string, string> = {
  reserved: "예약자 명단", cancelled: "취소 예약자 명단", no_show: "미참석자 명단", completed: "헌혈완료 명단",
  ineligible: "헌혈불가 명단", walkins: "비예약자 명단", reservation_completed: "예약 헌혈완료 명단", walkin_completed: "비예약 헌혈완료 명단",
};
const time = (value?: string) => value ? new Date(value).toLocaleString("ko-KR", { hour12: false }) : "-";
const csv = (value: unknown) => `"${String(value ?? "").replaceAll('"', '""')}"`;
const statusText = (row: any) => row.reservation_status === "cancelled" ? "취소" : row.reservation_status === "no_show" ? "미참석" : row.donation_status === "completed" ? "헌혈완료" : row.donation_status === "ineligible" ? "헌혈불가" : row.reservation_status === "checked_in" ? "참석" : "예약";

export default function StatisticsPage() {
  const [data, setData] = useState<any>();
  const [message, setMessage] = useState("");
  const [selected, setSelected] = useState<string>();
  const load = async () => {
    setMessage(""); setSelected(undefined);
    const { data: statistics, error } = await supabase.rpc("current_event_statistics");
    if (error) return setMessage(`통계를 불러오지 못했습니다: ${error.message}`);
    if (!statistics) return setMessage("현재 활성화된 행사가 없습니다.");
    setData(statistics);
  };
  useEffect(() => { load(); }, []);
  const downloadExcel = () => {
    if (!data) return;
    const rows = [
      ["헌혈행사 요청시점 통계"], ["행사명", data.event.title], ["헌혈행사일", data.event.event_date], ["조회시각", time(data.generated_at)], [],
      ["구분", "인원"], ...summaryCards.map(([key, title]) => [title, data.summary[key]]), [],
      ["시간대", "예약 가능", "예약", "참석", "헌혈완료", "헌혈불가", "미참석"], ...data.slots.map((slot: any) => [slot.slot_time?.slice(0, 5), slot.capacity, slot.reserved, slot.checked_in, slot.completed, slot.ineligible, slot.no_show]), [],
      ["근무처별 헌혈완료 현황", "인원"], ...data.workplaces.map((workplace: any) => [workplace.workplace, workplace.count]),
    ];
    const file = new Blob(["\uFEFF" + rows.map(row => row.map(csv).join(",")).join("\r\n")], { type: "text/csv;charset=utf-8" });
    const link = document.createElement("a"); link.href = URL.createObjectURL(file); link.download = `헌혈행사_통계_${data.event.event_date}.csv`; link.click(); URL.revokeObjectURL(link.href);
  };
  if (message) return <main className="page admin"><Header /><a href="/admin" style={{ color: "#1e4fa3" }}>← 관리자 메뉴</a><h1>통계</h1><p style={{ color: "#bd293b" }}>{message}</p></main>;
  if (!data) return <main className="page admin"><Header /><p className="hint">통계를 불러오는 중입니다.</p></main>;
  const selectedRows = selected ? data.details?.[selected] || [] : [];
  return <main className="page admin statistics">
    <Header /><a className="no-print" href="/admin" style={{ color: "#1e4fa3" }}>← 관리자 메뉴</a>
    <div className="statistics-head"><div><h1>헌혈행사 통계</h1><p className="hint">{data.event.title} · 헌혈행사일 {data.event.event_date}<br />조회 시각: {time(data.generated_at)}</p></div><div className="statistics-actions no-print"><button className="small-btn" onClick={load}>새로고침</button><button className="small-btn" onClick={downloadExcel}>엑셀용 다운로드</button><button className="small-btn" onClick={() => window.print()}>PDF로 저장</button></div></div>
    <p className="hint no-print">원하는 현황 블록을 누르면 아래에 해당 명단이 표시됩니다.</p>
    <section><h2>행사 현황</h2><div className="admin-grid">{summaryCards.map(([key, title]) => <button type="button" className="stat" key={key} onClick={() => key !== "available" && setSelected(selected === key ? undefined : key)} style={{ border: selected === key ? "2px solid #1e4fa3" : "1px solid #e5e9f0", background: "white", textAlign: "left", cursor: key === "available" ? "default" : "pointer" }}><span className="hint">{title}</span><b style={{ display: "block", fontSize: "1.3rem", marginTop: 7 }}>{data.summary[key] || 0}명</b>{key !== "available" && <span className="hint" style={{ fontSize: ".78rem" }}>명단 보기</span>}</button>)}</div></section>
    {selected && <section className="card" style={{ marginTop: 18 }}><div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12 }}><h2>{detailTitles[selected]}</h2><button className="small-btn no-print" onClick={() => setSelected(undefined)}>닫기</button></div>{selectedRows.length ? <table><thead><tr><th>이름</th><th>전화번호</th><th>사번</th><th>근무처</th><th>예약 시간</th><th>등록 구분</th><th>현재 상태</th></tr></thead><tbody>{selectedRows.map((row: any, index: number) => <tr key={`${row.registration_type}-${row.id || index}`}><td>{row.name}</td><td><a href={`tel:${row.phone}`}>{row.phone}</a></td><td>{row.employee_id || "-"}</td><td>{row.workplace || "미입력"}</td><td>{row.slot_time?.slice(0, 5) || "-"}</td><td>{row.registration_type}</td><td>{statusText(row)}</td></tr>)}</tbody></table> : <p className="hint">해당 인원이 없습니다.</p>}</section>}
    <section className="card" style={{ marginTop: 18 }}><h2>시간대별 현황</h2><table><thead><tr><th>시간</th><th>예약</th><th>참석</th><th>완료</th><th>불가</th><th>미참석</th></tr></thead><tbody>{data.slots.map((slot: any) => <tr key={slot.slot_time}><td>{slot.slot_time?.slice(0, 5)}</td><td>{slot.reserved}/{slot.capacity}</td><td>{slot.checked_in}</td><td>{slot.completed}</td><td>{slot.ineligible}</td><td>{slot.no_show}</td></tr>)}</tbody></table></section>
    <section className="card" style={{ marginTop: 18 }}><h2>근무처별 헌혈완료 현황</h2>{data.workplaces.length ? <table><thead><tr><th>근무처</th><th>헌혈완료 인원</th></tr></thead><tbody>{data.workplaces.map((workplace: any) => <tr key={workplace.workplace}><td>{workplace.workplace}</td><td>{workplace.count}명</td></tr>)}</tbody></table> : <p className="hint">헌혈완료 처리된 직원이 없습니다.</p>}</section>
  </main>;
}
