Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' }});
  }
  try {
    const BREVO_API_KEY = Deno.env.get('BREVO_API_KEY');
    const SENDER_EMAIL  = Deno.env.get('BREVO_SENDER_EMAIL');
    const body = await req.json();
    const { email, trackingNumber, labelUrl, carrier, service, recipientName, recipientCity } = body;

    if (!email || !trackingNumber || !labelUrl) {
      return Response.json({ success: false, error: 'Missing required fields' }, { status: 400 });
    }

    const htmlContent = [
      '<div style="font-family:sans-serif;max-width:500px;margin:0 auto;padding:24px">',
      '<h2 style="color:#FF5A00">Your label is ready!</h2>',
      '<p><strong>Tracking:</strong> ' + trackingNumber + '</p>',
      '<p><strong>Carrier:</strong> ' + carrier + ' - ' + service + '</p>',
      '<p><strong>To:</strong> ' + recipientName + ', ' + recipientCity + '</p>',
      '<a href="' + labelUrl + '" style="display:inline-block;margin-top:16px;padding:12px 24px;background:#6D28D9;color:white;border-radius:8px;text-decoration:none;font-weight:bold">Download Label PDF</a>',
      '<p style="color:#999;font-size:12px;margin-top:24px">Print this label and attach it securely to your parcel.</p>',
      '</div>',
    ].join('');

    const res = await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: {
        'api-key': BREVO_API_KEY,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        sender: { name: 'SwiftLabel', email: SENDER_EMAIL },
        to: [{ email: email }],
        subject: 'Your Shipping Label - ' + trackingNumber,
        htmlContent: htmlContent,
      }),
    });

    if (res.ok) {
      return Response.json({ success: true });
    }
    const err = await res.json();
    return Response.json({ success: false, error: err.message }, { status: 400 });
  } catch (e) {
    return Response.json({ success: false, error: e.message }, { status: 500 });
  }
});
