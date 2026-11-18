// Real HTTP + isolated database; mail stays in this local test mailbox.
import http from 'node:http';
import {readFile,writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import pg from 'pg';
import {createServer} from 'vite';
import {createTeamStore} from '../../server/teams/store.js';
import {createTeamHandler} from '../../server/teams/handlers.js';
const databaseURL=process.env.EXP_TEAM_TEST_DATABASE_URL;
const socket=databaseURL && new URL(databaseURL).searchParams.get('host');
if(!socket?.startsWith('/tmp/exp-team-test.') || process.env.NODE_ENV==='production')throw new Error('Use the isolated team preview runner');
const origin='http://127.0.0.1:5191',pool=new pg.Pool({connectionString:databaseURL});
await pool.query(await readFile(new URL('../../migrations/013_team_research.sql',import.meta.url),'utf8'));
await pool.query(await readFile(new URL('../../migrations/014_team_research_inbox.sql',import.meta.url),'utf8'));
const mailbox=[];
const handler=createTeamHandler({env:{TEAM_RESEARCH_ENABLED:'true',TEAM_RESEARCH_POLICY:'team-research-90d-v1',EXP_INTEREST_DATABASE_URL:databaseURL,INTEREST_PUBLIC_ORIGIN:origin,RESEND_API_KEY:'local-only',SIGNUP_FROM_EMAIL:'test@example.test',NODE_ENV:'development'},storeFactory:()=>createTeamStore(pool),mailer:async(config,email,links)=>{mailbox.push({email,...links});await writeFile(`${socket}/mailbox.json`,JSON.stringify(mailbox),{mode:0o600});}});
const vite=await createServer({root:fileURLToPath(new URL('..',import.meta.url)),server:{middlewareMode:true},appType:'spa'});
const server=http.createServer(async(request,response)=>{
 if(request.url==='/api/account'){response.writeHead(200,{'content-type':'application/json'});response.end(JSON.stringify({ok:true,user:null,registrationOpen:false}));return;}
 if(request.url!=='/api/team-research')return vite.middlewares(request,response);
 let body='';for await(const chunk of request){body+=chunk;if(Buffer.byteLength(body)>12000){response.writeHead(413).end();return;}}
 request.body=body;await handler(request,response);
});
server.listen(5191,'127.0.0.1',()=>console.log(`Preview: ${origin}/teams\nCaptured mail: ${socket}/mailbox.json`));
async function close(){server.close();await vite.close();await pool.end();process.exit(0);}
process.on('SIGINT',close);process.on('SIGTERM',close);
