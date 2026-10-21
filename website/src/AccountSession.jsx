import React,{createContext,useCallback,useContext,useEffect,useRef,useState} from 'react';
import accountRequest from './account-request.js';

const Context=createContext(null);
export const useAccountSession=()=>useContext(Context);
export function AccountSessionProvider({children}) {
  const [state,setState]=useState({ready:false,available:false,user:null,registrationOpen:false,engagementOpen:false,error:''});
  const flight=useRef(null),generation=useRef(0),channel=useRef(null),lastLoad=useRef(0);
  const refresh=useCallback((force=false,announce=false)=>{
    if(flight.current && !force)return flight.current;
    const version=++generation.current;lastLoad.current=Date.now();
    if(announce)channel.current?.postMessage('changed');
    const request=accountRequest().then(result=>{
      if(version===generation.current)setState({ready:true,available:true,user:result.user,registrationOpen:result.registrationOpen,engagementOpen:result.engagementOpen===true,error:''});
      return result;
    }).catch(error=>{
      if(version===generation.current)setState({ready:true,available:false,user:null,registrationOpen:false,engagementOpen:false,error:error.message});
      throw error;
    }).finally(()=>{if(version===generation.current)flight.current=null;});
    flight.current=request;return request;
  },[]);
  const clear=useCallback(()=>{
    generation.current++;flight.current=null;
    setState(current=>({...current,ready:true,user:null,error:''}));channel.current?.postMessage('changed');
  },[]);
  useEffect(()=>{
    refresh().catch(()=>{});
    if('BroadcastChannel' in window){
      channel.current=new BroadcastChannel('exp-account-session');
      channel.current.onmessage=event=>{if(event.data==='changed')refresh(true).catch(()=>{});};
    }
    const focus=()=>{if(document.visibilityState==='visible' && Date.now()-lastLoad.current>30000)refresh(true).catch(()=>{});};
    window.addEventListener('focus',focus);document.addEventListener('visibilitychange',focus);
    return()=>{channel.current?.close();channel.current=null;window.removeEventListener('focus',focus);document.removeEventListener('visibilitychange',focus);};
  },[refresh]);
  return <Context.Provider value={{...state,refresh,clear}}>{children}</Context.Provider>;
}
