import {timingSafeEqual} from 'node:crypto';
import {processTicketMail} from './ticket-mail.js';
import {accountRetention,accountRetentionVersion} from './retention.js';

const json=(response,status,body)=>{response.writeHead(status,{'Content-Type':'application/json','Cache-Control':'no-store','Referrer-Policy':'no-referrer','X-Robots-Tag':'noindex'}).end(JSON.stringify(body));};
export function authorizedJob(request,secret) {
  if(typeof secret!=='string' || secret.length<32)return false;
  const expected=Buffer.from(`Bearer ${secret}`),received=Buffer.from(typeof request.headers.authorization==='string'?request.headers.authorization:'');
  return received.length===expected.length && timingSafeEqual(received,expected);
}
export function createAccountJobHandler({pool,env,send}) {
  return async(request,response)=>{
    if(!authorizedJob(request,env.EXP_ACCOUNT_JOB_TOKEN))return json(response,401,{error:'Job authorization required.'});
    if(request.method!=='POST')return json(response,405,{error:'Use POST.'});
    if(request.headers['content-type']?.split(';')[0]!=='application/json')return json(response,415,{error:'Use JSON.'});
    let body;
    try{
      if(request.body!==undefined){
        const raw=typeof request.body==='string'?request.body:JSON.stringify(request.body);
        if(Buffer.byteLength(raw)>2048)return json(response,413,{error:'Request too large.'});
        body=JSON.parse(raw);
      }else{
        const chunks=[];let size=0;
        for await(const chunk of request){size+=chunk.length;if(size>2048)return json(response,413,{error:'Request too large.'});chunks.push(chunk);}
        body=JSON.parse(Buffer.concat(chunks).toString('utf8'));
      }
    }catch{return json(response,400,{error:'Invalid job request.'});}
    if(!body || Array.isArray(body) || typeof body!=='object' || Object.keys(body).length!==1 || !['preview','mail','retention'].includes(body.operation))return json(response,400,{error:'Invalid job request.'});
    if(body.operation==='mail' && (env.ACCOUNT_TICKET_MAIL_ENABLED!=='true' || !env.RESEND_API_KEY || !env.SIGNUP_FROM_EMAIL))return json(response,503,{error:'Ticket notifications are paused.'});
    if(body.operation==='retention' && (env.ACCOUNT_RETENTION_ENABLED!=='true' || env.ACCOUNT_RETENTION_POLICY!==accountRetentionVersion))return json(response,503,{error:'Retention is paused or its policy is not approved.'});
    try{
      if(body.operation==='mail'){
        const ticketMail=await processTicketMail({pool,enabled:true,origin:env.ACCOUNT_PUBLIC_ORIGIN,from:env.SIGNUP_FROM_EMAIL,send});
        return json(response,ticketMail.failed?502:200,{ok:ticketMail.failed===0,ticketMail});
      }
      const retention=await accountRetention({pool,apply:body.operation==='retention',enabled:env.ACCOUNT_RETENTION_ENABLED==='true',policy:env.ACCOUNT_RETENTION_POLICY});
      const queue=body.operation==='preview'?(await pool.query('SELECT state,count(*)::integer AS count FROM exp_member_ticket_mail GROUP BY state ORDER BY state')).rows:undefined;
      return json(response,200,{ok:true,retention,...(queue?{queue}:{})});
    }catch{return json(response,503,{error:'Account job is unavailable. No completion is assumed.'});}
  };
}
