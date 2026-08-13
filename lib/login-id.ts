export const LOGIN_ID_PATTERN = /^[a-z0-9][a-z0-9_-]{2,29}$/;
export function isLoginId(value: string) { return LOGIN_ID_PATTERN.test(value); }
export function internalEmail(loginId: string) { return `${loginId.toLowerCase()}@sch-blood-booking.internal`; }
export function authIdentifier(value: string) { return value.includes("@") ? value.trim() : internalEmail(value.trim()); }
