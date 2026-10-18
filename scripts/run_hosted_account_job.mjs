// GitHub holds only a job token. DB and Resend credentials stay inside Vercel.
const operation=process.argv[2];
try{
  if(!['preview','mail','retention'].includes(operation) || !process.env.EXP_ACCOUNT_JOB_TOKEN || process.env.EXP_ACCOUNT_JOB_TOKEN.length<32)throw new Error('Invalid configuration');
  const url=new URL(process.env.EXP_ACCOUNT_JOB_URL || 'https://expdesign.app/api/account-jobs');
  const local=process.env.NODE_ENV!=='production' && url.protocol==='http:' && url.hostname==='127.0.0.1';
  if(url.username || url.password || url.search || url.hash || url.pathname!=='/api/account-jobs' || (!local && url.origin!=='https://expdesign.app'))throw new Error('Invalid destination');
  const response=await fetch(url,{method:'POST',redirect:'error',signal:AbortSignal.timeout(150000),
    headers:{Authorization:`Bearer ${process.env.EXP_ACCOUNT_JOB_TOKEN}`,'Content-Type':'application/json'},body:JSON.stringify({operation})});
  if(!response.ok)throw new Error('Remote job failed');
  const body=await response.json();
  if(body?.ok!==true)throw new Error('No completion');
  const counts=body.ticketMail??body.retention?.counts;
  const keys=operation==='mail'?['accepted','retry','failed','skipped']:['sessions','challenges','authLimits','mailLimits','betaLimits','communityLimits','ticketLimits','closedTickets','betaFeedback','resolvedReports','supportAudit','mailReceipts'];
  if(!counts || keys.some(key=>!Number.isSafeInteger(counts[key]) || counts[key]<0))throw new Error('Invalid receipt');
  // Explicit projection: never echo a server error/body or unexpected private fields.
  console.log(JSON.stringify({operation,counts:Object.fromEntries(keys.map(key=>[key,counts[key]]))}));
}catch{process.exitCode=1;console.error('Hosted account job failed. Check authorization, rollout flags and private service logs. No success is assumed.');}
