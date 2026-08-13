import { createClient } from "@supabase/supabase-js";
import { authIdentifier } from "@/lib/login-id";
// Placeholder values let Vercel build before its environment variables are attached.
export const supabase = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL || "https://placeholder.supabase.co", process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || "placeholder-anon-key");
const originalSignIn = supabase.auth.signInWithPassword.bind(supabase.auth);
supabase.auth.signInWithPassword = ((credentials: { email: string; password: string }) => originalSignIn({ ...credentials, email: authIdentifier(credentials.email) })) as typeof supabase.auth.signInWithPassword;
export type EventInfo = { id:string; title:string; event_date:string; location:string; active:boolean; eligibility_url:string|null; questionnaire_url?:string|null; privacy_purpose:string; privacy_retention:string; privacy_disposal:string };
export type Slot = { id:string; slot_time:string; capacity:number; enabled:boolean; booked:number };
export const phoneOnly = (value:string) => value.replace(/[^0-9]/g, "");
