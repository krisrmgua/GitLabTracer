const board = require('./menu-board.cjs');
module.exports = async (_root,output) => {
  const {trayCapsulePng}=require('../../dist-electron/trayCapsule.js');
  const {trayIconPng}=require('../../dist-electron/icons.js');
  const rows=[];
  for(const [label,status,progress,failed] of [['Passed','passed',1,false],['Running · progress ring','running',.55,false],['Queued','pending',0,false],['Failed · attention','failed',1,true],['Canceled','canceled',1,false],['Skipped','skipped',1,false]]) rows.push({label,png:trayIconPng(status,progress,failed,36,[],0)});
  for(const [label,status,progress,counts] of [
    ['Multiple requests and active pipelines','running',.55,{mergeRequests:3,running:2,failed:1,mrTone:'running'}],
    ['Ready to merge','passed',1,{mergeRequests:1,running:0,failed:0,mrTone:'ready'}],
    ['Quiet state · zero counters hidden','passed',1,{mergeRequests:0,running:0,failed:0}],
  ]) rows.push({label,png:(await trayCapsulePng(status,progress,counts.failed>0,counts)).png});
  return board(output,'menu-bar.png','Pipeline Tracer · icons and counters',rows,'Production menu-bar icons for passed, running, queued, failed, canceled, and skipped states, plus populated and quiet counter capsules.');
};
