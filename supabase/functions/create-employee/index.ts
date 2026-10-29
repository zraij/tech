import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return Response.json({ error: "Method not allowed" }, { status: 405, headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace(/^Bearer\s+/i, "");
    if (!token) return Response.json({ error: "Unauthorized" }, { status: 401, headers: cors });

    const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
    const { data: { user }, error: authError } = await admin.auth.getUser(token);
    if (authError || !user) return Response.json({ error: "Unauthorized" }, { status: 401, headers: cors });
    const { data: profile } = await admin.from("staff_profiles").select("role").eq("id", user.id).maybeSingle();
    if (profile?.role !== "admin") return Response.json({ error: "المشرف فقط ينشئ حسابات الموظفين" }, { status: 403, headers: cors });

    const body = await req.json();
    const email = String(body.email || "").trim().toLowerCase();
    const password = String(body.password || "");
    const displayName = String(body.display_name || "").trim();
    if (!email || password.length < 8 || !displayName) {
      return Response.json({ error: "أدخل الاسم والبريد وكلمة مرور من 8 أحرف على الأقل" }, { status: 400, headers: cors });
    }

    const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
    if (error) return Response.json({ error: error.message }, { status: 400, headers: cors });
    const { error: profileError } = await admin.from("staff_profiles").insert({ id: data.user.id, display_name: displayName, role: "employee" });
    if (profileError) {
      await admin.auth.admin.deleteUser(data.user.id);
      return Response.json({ error: profileError.message }, { status: 500, headers: cors });
    }
    return Response.json({ id: data.user.id, email }, { status: 200, headers: cors });
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "Unexpected error" }, { status: 500, headers: cors });
  }
});
