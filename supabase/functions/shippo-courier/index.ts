import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' } });
  }
  try {
    const SHIPPO_API_KEY = Deno.env.get('SHIPPO_API_KEY');
    if (!SHIPPO_API_KEY) return Response.json({ error: 'SHIPPO_API_KEY not set' }, { status: 500 });

    const body = await req.json();
    const { action } = body;
    const shippoHeaders = { Authorization: `ShippoToken ${SHIPPO_API_KEY}`, 'Content-Type': 'application/json' };

    if (action === 'get_rates') {
      const { shipment } = body;
      const parcel = _buildParcel(shipment.parcel);
      const res = await fetch('https://api.goshippo.com/shipments/', { method: 'POST', headers: shippoHeaders, body: JSON.stringify({ address_from: { name: shipment.sender.name, street1: shipment.sender.address, city: shipment.sender.city, zip: shipment.sender.postcode, country: 'GB', phone: shipment.sender.phone }, address_to: { name: shipment.recipient.name, street1: shipment.recipient.address, city: shipment.recipient.city, zip: shipment.recipient.postcode, country: 'GB', phone: shipment.recipient.phone }, parcels: [parcel], async: false }) });
      if (!res.ok) return Response.json({ error: 'Failed to get rates' }, { status: 500 });
      const data = await res.json();
      const rates = (data.rates || []).sort((a: any, b: any) => parseFloat(a.amount) - parseFloat(b.amount)).map((r: any) => ({ rateId: r.object_id, carrier: r.provider, service: r.servicelevel?.name, price: parseFloat(r.amount), currency: r.currency, estimatedDays: r.estimated_days, dropoff: 'Drop-off' }));
      return Response.json({ success: true, shipmentId: data.object_id, rates });
    }

    if (action === 'create_label') {
      const { shipment, carrier } = body;
      const parcel = _buildParcel(shipment.parcel);
      const shipRes = await fetch('https://api.goshippo.com/shipments/', { method: 'POST', headers: shippoHeaders, body: JSON.stringify({ address_from: { name: shipment.sender.name, street1: shipment.sender.address, city: shipment.sender.city, zip: shipment.sender.postcode, country: 'GB', phone: shipment.sender.phone, email: shipment.sender.email || '' }, address_to: { name: shipment.recipient.name, street1: shipment.recipient.address, city: shipment.recipient.city, zip: shipment.recipient.postcode, country: 'GB', phone: shipment.recipient.phone }, parcels: [parcel], async: false }) });
      if (!shipRes.ok) return Response.json({ success: false, error: 'Failed to create shipment' }, { status: 500 });
      const shipData = await shipRes.json();
      const rates = shipData.rates || [];
      let selectedRate = carrier ? rates.find((r: any) => r.provider.toLowerCase().includes(carrier.toLowerCase())) : null;
      if (!selectedRate && rates.length > 0) selectedRate = rates.sort((a: any, b: any) => parseFloat(a.amount) - parseFloat(b.amount))[0];
      if (!selectedRate) return Response.json({ success: false, error: 'No rates available' }, { status: 500 });
      const txRes = await fetch('https://api.goshippo.com/transactions/', { method: 'POST', headers: shippoHeaders, body: JSON.stringify({ rate: selectedRate.object_id, label_file_type: 'PDF', async: false }) });
      if (!txRes.ok) return Response.json({ success: false, error: 'Failed to purchase label' }, { status: 500 });
      const tx = await txRes.json();
      if (tx.status !== 'SUCCESS') return Response.json({ success: false, error: tx.messages?.[0]?.text || 'Label failed' }, { status: 500 });
      return Response.json({ success: true, tracking_number: tx.tracking_number, label_url: tx.label_url, carrier: selectedRate.provider, service: selectedRate.servicelevel?.name, estimated_days: selectedRate.estimated_days, cost: selectedRate.amount, currency: selectedRate.currency });
    }

    if (action === 'track') {
      const { trackingNumber, carrier } = body;
      if (!trackingNumber) return Response.json({ error: 'trackingNumber required' }, { status: 400 });
      const resolvedCarrier = carrier || _detectCarrier(trackingNumber);
      const res = await fetch(`https://api.goshippo.com/tracks/${resolvedCarrier}/${trackingNumber}`, { headers: { Authorization: `ShippoToken ${SHIPPO_API_KEY}` } });
      if (!res.ok) return Response.json({ success: false, error: 'Tracking not available' }, { status: 404 });
      const data = await res.json();
      const events = (data.tracking_history || []).map((e: any) => ({ status: e.status, message: e.status_details || e.status, location: e.location?.city ? `${e.location.city}, ${e.location.country}` : e.location?.country || 'Unknown', timestamp: e.status_date }));
      return Response.json({ success: true, tracking: data, trackingNumber: data.tracking_number, carrier: data.carrier, servicelevel: data.servicelevel?.name, status: data.tracking_status?.status, statusDetails: data.tracking_status?.status_details, eta: data.eta, originLocation: data.address_from ? `${data.address_from.city}, ${data.address_from.country}` : null, destLocation: data.address_to ? `${data.address_to.city}, ${data.address_to.country}` : null, events });
    }

    return Response.json({ error: 'Invalid action' }, { status: 400 });
  } catch (e: any) {
    return Response.json({ success: false, error: e.message }, { status: 500 });
  }
});

function _buildParcel(parcel: any) {
  const dims: any = { xs: { l: 15, w: 11, h: 1 }, sm: { l: 45, w: 35, h: 16 }, md: { l: 61, w: 46, h: 46 }, lg: { l: 120, w: 60, h: 60 } };
  const sizeMap: any = { small: 'sm', large: 'lg', medium: 'md', 'extra small': 'xs' };
  const key = sizeMap[parcel.size?.toLowerCase()] || parcel.size || 'sm';
  const d = dims[key] || dims['sm'];
  return { length: String(d.l), width: String(d.w), height: String(d.h), distance_unit: 'cm', weight: String(parcel.weight_kg || 1), mass_unit: 'kg' };
}

function _detectCarrier(code: string): string {
  const u = code.toUpperCase();
  if (u.startsWith('RM')) return 'royal_mail';
  if (u.startsWith('EV')) return 'evri';
  if (u.startsWith('DP')) return 'dpd';
  if (u.startsWith('DH')) return 'dhl_express';
  if (u.startsWith('IP')) return 'inpost';
  if (u.startsWith('YD')) return 'yodel';
  return 'royal_mail';
}
