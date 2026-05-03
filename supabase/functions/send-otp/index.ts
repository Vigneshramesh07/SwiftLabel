import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

function generateOtp() {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
      },
    });
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const body = await req.json();
    const { email, action, otp: submittedOtp } = body;

    if (!email) {
      return Response.json({ error: 'Email is required' }, { status: 400 });
    }

    const normalizedEmail = email.toLowerCase().trim();

    if (action === 'verify') {
      const { data: records } = await supabase
        .from('otp_codes')
        .select('*')
        .eq('email', normalizedEmail)
        .order('created_at', { ascending: false })
        .limit(1);

      if (!records || records.length === 0) {
        return Response.json(
          { error: 'No code found. Please request a new one.' },
          { status: 400 },
        );
      }

      const record = records[0];

      if (new Date() > new Date(record.expires_at)) {
        await supabase.from('otp_codes').delete().eq('id', record.id);
        return Response.json(
          { error: 'Code has expired. Please request a new one.' },
          { status: 400 },
        );
      }

      if (record.code !== submittedOtp) {
        return Response.json(
          { error: 'Incorrect code. Please try again.' },
          { status: 400 },
        );
      }

      await supabase.from('otp_codes').delete().eq('id', record.id);

      const tokenBytes = new Uint8Array(32);
      crypto.getRandomValues(tokenBytes);
      const sessionToken = Array.from(tokenBytes)
        .map((b) => b.toString(16).padStart(2, '0'))
        .join('');
      const sessionExpiry = new Date(
        Date.now() + 7 * 24 * 60 * 60 * 1000,
      ).toISOString();

      await supabase
        .from('session_tokens')
        .delete()
        .eq('identifier', normalizedEmail);

      await supabase.from('session_tokens').insert({
        identifier: normalizedEmail,
        login_type: 'email',
        token: sessionToken,
        expires_at: sessionExpiry,
      });

      await supabase
        .from('users')
        .upsert({ email: normalizedEmail }, { onConflict: 'email' });

      return Response.json({
        success: true,
        sessionToken,
        identifier: normalizedEmail,
      });
    }

    await supabase.from('otp_codes').delete().eq('email', normalizedEmail);

    const otp = generateOtp();
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();

    await supabase.from('otp_codes').insert({
      email: normalizedEmail,
      code: otp,
      expires_at: expiresAt,
    });

    const htmlBody = `
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
      </head>
      <body style="margin:0;padding:0;background-color:#f3f4f6;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Arial,sans-serif;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#f3f4f6;padding:40px 20px;">
          <tr>
            <td align="center">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:500px;background-color:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 6px rgba(0,0,0,0.07);">
                <tr>
                  <td style="background:linear-gradient(135deg,#f97316 0%,#fb923c 100%);padding:32px 40px;text-align:center;">
                    <h1 style="margin:0;font-size:24px;font-weight:700;color:#ffffff;">SwiftLabel</h1>
                  </td>
                </tr>
                <tr>
                  <td style="padding:40px;">
                    <h2 style="margin:0 0 16px 0;font-size:22px;font-weight:700;color:#111827;text-align:center;">Verify Your Email</h2>
                    <p style="margin:0 0 32px 0;font-size:15px;line-height:24px;color:#4b5563;text-align:center;">Use the one-time code below to securely access your shipments.</p>
                    <div style="background-color:#fef3c7;border:3px solid #f59e0b;border-radius:12px;padding:24px;text-align:center;margin:0 0 32px 0;">
                      <div style="font-size:42px;font-weight:800;letter-spacing:12px;color:#111827;font-family:'Courier New',monospace;">${otp}</div>
                    </div>
                    <div style="background-color:#fef2f2;border-left:4px solid #dc2626;border-radius:8px;padding:16px;margin:0 0 24px 0;">
                      <p style="margin:0 0 8px 0;font-size:13px;font-weight:600;color:#991b1b;">🔒 Security Notice</p>
                      <p style="margin:0;font-size:13px;line-height:20px;color:#7f1d1d;">This code expires in <strong>10 minutes</strong>. Do not share it.</p>
                    </div>
                    <p style="margin:0;font-size:13px;color:#6b7280;text-align:center;">If you did not request this, ignore this email.</p>
                  </td>
                </tr>
                <tr>
                  <td style="background-color:#f9fafb;padding:24px 40px;border-top:1px solid #e5e7eb;">
                    <p style="margin:0;font-size:13px;color:#6b7280;text-align:center;">
                      Need help? <a href="mailto:support@swiftlabel.co.uk" style="color:#f97316;text-decoration:none;font-weight:600;">support@swiftlabel.co.uk</a>
                    </p>
                    <p style="margin:8px 0 0 0;font-size:12px;color:#9ca3af;text-align:center;">© 2026 SwiftLabel. All rights reserved.</p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
        </table>
      </body>
      </html>
    `;

    const brevoRes = await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: {
        'api-key': Deno.env.get('BREVO_API_KEY')!,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        sender: {
          name: 'SwiftLabel',
          email: Deno.env.get('BREVO_SENDER_EMAIL'),
        },
        to: [{ email: normalizedEmail }],
        subject: 'Your secure login code for SwiftLabel',
        htmlContent: htmlBody,
      }),
    });

    if (!brevoRes.ok) {
      const err = await brevoRes.text();
      console.error('Brevo error:', err);
      return Response.json(
        { error: 'Failed to send email. Please try again.' },
        { status: 500 },
      );
    }

    console.log(`OTP sent to ${normalizedEmail}`);
    return Response.json({ success: true, message: 'Code sent successfully' });

  } catch (error) {
    console.error('Error:', error.message);
    return Response.json(
      { error: 'Failed to process request: ' + error.message },
      { status: 500 },
    );
  }
});
