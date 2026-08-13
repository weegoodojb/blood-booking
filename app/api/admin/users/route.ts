import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { internalEmail, isLoginId } from "@/lib/login-id";

const url=process.env.NEXT_PUBLIC_SUPABASE_URL;
const secret=process.env.SUPABASE_SECRET_KEY;
const admin=()=>createClient(url!,secret!,{auth:{autoRefreshToken:false,persistSession:false}});
async function authorize(request:NextRequest){
 if(!url||!secret) return {error:"서버의 SUPABASE_SECRET_KEY 환경변수가 설정되지 않았습니다."};
 const token=request.headers.get("authorization")?.replace("Bearer ",""); if(!token)return {error:"로그인이 필요합니다."};
 const publicClient=createClient(url,process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);
 const {data:{user}}=await publicClient.auth.getUser(token); if(!user)return {error:"로그인이 필요합니다."};
 const {data,error}=await admin().from("user_roles").select("role").eq("user_id",user.id).maybeSingle();
 if(error?.code==='42P01')return {error:"권한 설정 SQL이 아직 설치되지 않았습니다. operator-management-migration.sql 전체를 실행해주세요."};
 return data?.role==='system_admin'?{user}:{error:`현재 로그인한 계정(${user.email})은 시스템 관리자로 등록되지 않았습니다. Supabase SQL Editor에서 system_admin 등록 SQL을 한 번 실행해주세요.`};
}
async function findUser(loginId:string){
 const {data,error}=await admin().auth.admin.listUsers({page:1,perPage:1000}); if(error)throw error;
 return data.users.find(user=>user.user_metadata?.login_id===loginId||user.email===internalEmail(loginId));
}
export async function GET(request:NextRequest){const auth=await authorize(request);if('error'in auth)return NextResponse.json(auth,{status:403});const {data:roles,error}=await admin().from('user_roles').select('user_id,role').order('created_at');if(error)return NextResponse.json({error:error.message},{status:400});const {data:users}=await admin().auth.admin.listUsers({page:1,perPage:1000});return NextResponse.json({users:(roles||[]).map(role=>{const user=users.users.find(x=>x.id===role.user_id);return {id:role.user_id,loginId:user?.user_metadata?.login_id||user?.email,role:role.role}})});}
export async function POST(request:NextRequest){const auth=await authorize(request);if('error'in auth)return NextResponse.json(auth,{status:403});const body=await request.json();const loginId=String(body.loginId||'').toLowerCase(),password=String(body.password||'');if(!isLoginId(loginId))return NextResponse.json({error:'아이디는 영문 소문자·숫자·_·-로 3~30자 입력해주세요.'},{status:400});if(password.length<8)return NextResponse.json({error:'비밀번호는 8자 이상으로 입력해주세요.'},{status:400});if(await findUser(loginId))return NextResponse.json({error:'이미 사용 중인 아이디입니다.'},{status:400});const {data,error}=await admin().auth.admin.createUser({email:internalEmail(loginId),password,email_confirm:true,user_metadata:{login_id:loginId}});if(error||!data.user)return NextResponse.json({error:error?.message||'계정 생성에 실패했습니다.'},{status:400});await admin().from('user_roles').insert({user_id:data.user.id,role:'event_manager'});return NextResponse.json({ok:true});}
export async function PATCH(request:NextRequest){const auth=await authorize(request);if('error'in auth)return NextResponse.json(auth,{status:403});const {loginId,password}=await request.json();if(!isLoginId(String(loginId))||String(password).length<8)return NextResponse.json({error:'아이디 또는 비밀번호를 확인해주세요.'},{status:400});const user=await findUser(loginId);if(!user)return NextResponse.json({error:'사용자를 찾을 수 없습니다.'},{status:404});const {error}=await admin().auth.admin.updateUserById(user.id,{password});return error?NextResponse.json({error:error.message},{status:400}):NextResponse.json({ok:true});}
export async function DELETE(request:NextRequest){const auth=await authorize(request);if('error'in auth)return NextResponse.json(auth,{status:403});const {loginId}=await request.json();const user=await findUser(String(loginId));if(!user)return NextResponse.json({error:'사용자를 찾을 수 없습니다.'},{status:404});const {data:role}=await admin().from('user_roles').select('role').eq('user_id',user.id).maybeSingle();if(role?.role!=='event_manager')return NextResponse.json({error:'행사 진행자 계정만 삭제할 수 있습니다.'},{status:400});const {error}=await admin().auth.admin.deleteUser(user.id);return error?NextResponse.json({error:error.message},{status:400}):NextResponse.json({ok:true});}
