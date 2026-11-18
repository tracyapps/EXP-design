import { authorizedJob } from '../accounts/jobs.js';
import { interestConfiguration, sendJson } from '../interest/handlers.js';
import { configuredTeamStore } from './store.js';
import { notifyOwner, sendOwnerNotification } from './notifications.js';
export function createTeamJobHandler({env=process.env,storeFactory=configuredTeamStore,send=sendOwnerNotification}={}) {
  return async(request,response)=>{
    if(!authorizedJob(request,env.CRON_SECRET))return sendJson(response,{error:'Job authorization required.'},401);
    if(request.method!=='GET'){response.setHeader('allow','GET');return sendJson(response,{error:'Use GET.'},405);}
    const config=interestConfiguration(env,'withdraw');
    if(!config || env.TEAM_RESEARCH_POLICY!=='team-research-90d-v1')return sendJson(response,{error:'Research maintenance is not configured.'},503);
    try {
      const store=storeFactory(config.databaseURL);
      const retention=await store.cleanup(); // continues when new submissions are paused
      let sent=0,failed=0;
      if(env.TEAM_RESEARCH_NOTIFY_OWNER==='true' && config.apiKey && config.from) {
        for(let i=0;i<5;i++) {
          const result=await notifyOwner({store,config,send});
          sent+=result.sent;failed+=result.failed;
          if(!result.sent && !result.failed)break;
        }
      }
      return sendJson(response,{ok:failed===0,retention,notifications:{sent,failed}},failed?502:200);
    }catch{console.warn('Research maintenance unavailable');return sendJson(response,{error:'Research maintenance unavailable.'},503);}
  };
}
