/* W03 browser-only witness injected into disposable paired Wails package. */
(()=>{
  "use strict";
  const destination="__W03_BEACON_URL__",events=new Set(),pending=[];
  const send=(event)=>{
    if(events.has(event))return;
    events.add(event);
    const img=new Image();
    pending.push(img);
    img.src=destination+"&event="+encodeURIComponent(event)+"&t="+Date.now();
  };
  const read=async()=>{
    const r=await fetch("/api/paper/session",{credentials:"same-origin",cache:"no-store"});
    if(!r.ok)throw Error("status HTTP "+r.status);
    return r.json();
  };
  const waiting=async(check,limit=16000)=>{
    const until=Date.now()+limit;
    while(Date.now()<until){
      const result=await check();
      if(result)return result;
      await new Promise(resolve=>setTimeout(resolve,350));
    }
    throw Error("bounded witness timeout");
  };
  async function run(){
    send("w03_script_executed");
    await waiting(()=>window.KTRADE_APP?.pineEditor &&
      document.getElementById("paperSessionStart") &&
      document.getElementById("pineSave") &&
      document.getElementById("paperSessionStatus"));
    send("w03_native_paper_controls");
    let state=await read();
    if(state.schema!=="ktrade.paper.isolated-session.v1"||state.mode!=="PAPER_NOT_FUNDED"||
      state.live_armed!==false||state.paper_orders_enabled!==false ||
      document.getElementById("paperSessionStart").disabled ||
      !document.getElementById("paperSessionEvaluate").disabled ||
      !document.getElementById("paperSessionStop").disabled){
      send("w03_unfunded_guard_failed");return;
    }
    send("w03_unfunded_guard");
    document.getElementById("pineBtn").click();
    document.getElementById("symbolBtn").click();
    await waiting(()=>document.querySelector('#symbolResults .ritem[data-s="BTC-USDC"]'));
    document.querySelector('#symbolResults .ritem[data-s="BTC-USDC"]').click();
    if(window.KTRADE_APP.s.symbol!=="BTC-USDC"||window.KTRADE_APP.s.tf!=="1m"){
      send("w03_market_selector_failed");return;
    }
    send("w03_ui_market_selected");
    // Real Coinbase public FINAL candles remain authoritative. Pine's
    // supported barstate.islast selects the final confirmed input bar,
    // regardless of whether upstream finalized 299 or 300 candles.
    // Bounded spot PAPER size: never close to original $100 quote guard.
    const source='//@version=5\nstrategy("W03 Browser Final-Bar Paper", overlay=true)\nif barstate.islast\n    strategy.entry("L", strategy.long, qty=0.0001)\n';
    window.KTRADE_APP.pineEditor.setValue(source);
    if(window.KTRADE_APP.pineEditor.getValue()!==source){send("w03_editor_failed");return;}
    const priorPrompt=window.prompt;
    try {
      window.prompt=()=> "W03 disposable browser paper acceptance";
      document.getElementById("pineSave").click();
    } finally {window.prompt=priorPrompt;}
    const selected=await waiting(()=>{
      const s=window.KTRADE_PINE_SAVED_SELECTION;
      return s?.kind==="strategy" && s.ownership==="user" &&
        /^[a-f0-9]{32}$/.test(s.id)&&
        !document.getElementById("pineSavedIndicator").classList.contains("unsaved");
    });
    send("w03_ui_pine_durable_save");
    const panel=document.getElementById("paperSessionControls");
    const nums=Array.from(panel.querySelectorAll('input[type="number"]'));
    const checkbox=panel.querySelector('input[type="checkbox"]');
    if(nums.length!==2||!checkbox){send("w03_fee_controls_missing");return;}
    nums[0].value="600";nums[1].value="100";
    checkbox.checked=false;
    document.getElementById("paperSessionStart").click();
    await new Promise(resolve=>setTimeout(resolve,950));
    state=await read();
    if(state.mode!=="PAPER_NOT_FUNDED"||state.paper_orders_enabled!==false){
      send("w03_no_fee_guard_failed");return;
    }
    send("w03_ui_no_fee_start_refused");
    await waiting(()=>!document.getElementById("paperSessionStart").disabled,4000);
    checkbox.checked=true;
    document.getElementById("paperSessionStart").click();
    try {
      state=await waiting(async()=>{
        const x=await read();
        return x.mode==="PAPER_ISOLATED_RUNNING"?x:null;
      },17000);
    }catch(_){send("w03_funded_start_not_verified");return;}
    if(state.live_armed!==false||state.paper_orders_enabled!==true||
      document.getElementById("paperSessionStop")?.disabled!==false){
      send("w03_funded_authority_invalid");return;
    }
    send("w03_ui_explicit_paper_start");
    // Capture the actual response to the original UI button's POST, not
    // a separate synthetic request or a click-only proxy receipt.
    let verifiedBrowserFill=false;
    const oldFetch=window.fetch.bind(window);
    window.fetch=async (...args)=>{
      const response=await oldFetch(...args);
      if(args[0]==="/api/paper/session/evaluate"){
        try{
          const result=await response.clone().json();
          if(response.ok && result.schema==="ktrade.paper.isolated-session.v1" &&
            result.live_armed===false &&
            (result.outcome==="NO_SUPPORTED_FINAL_BAR_ORDER" ||
             result.outcome==="ISOLATED_PAPER_FILLED_OR_DEDUPLICATED")) {
            send("w03_evaluate_server_accepted");
            if(result.outcome==="ISOLATED_PAPER_FILLED_OR_DEDUPLICATED" &&
              result.paper_fill===true && result.fill_count===1 &&
              /^[a-f0-9]{64}$/.test(result.ledger_hash||"")){
              verifiedBrowserFill=true;
              send("w03_browser_finalbar_paper_fill");
            } else {
              send("w03_browser_no_source_verified_fill");
            }
          }else{send("w03_evaluate_server_refused");}
        }catch(_){send("w03_evaluate_server_refused");}
      }
      return response;
    };
    const evaluate=document.getElementById("paperSessionEvaluate");
    if(evaluate.disabled){send("w03_evaluate_control_disabled");return;}
    evaluate.click();
    await waiting(()=>events.has("w03_evaluate_server_accepted")||
      events.has("w03_evaluate_server_refused"),12000);
    if(!events.has("w03_evaluate_server_accepted"))return;
    send("w03_ui_evaluate_clicked");
    document.getElementById("paperSessionStop").click();
    const stopped=await waiting(async()=>{
      const x=await read();
      return x.stopped===true && x.paper_orders_enabled===false ? x:null;
    },13000);
    if(stopped.live_armed!==false){send("w03_stop_live_guard_failed");return;}
    send("w03_ui_paper_stop");
    const archive=await fetch("/api/paper/session/archive",{credentials:"same-origin",cache:"no-store"});
    if(archive.ok){
      const report=await archive.json();
      if(report.schema==="ktrade.paper.cold-archive.read-only.v1" &&
         report.live_armed===false && report.orders_enabled===false &&
         report.execution_restore_eligible===false &&
         report.requires_review===true &&
         report.account?.stopped===true &&
         Array.isArray(report.account.products)){
        send("w03_ui_sealed_archive");
        const product=report.account.products.find(x=>x.product_id==="BTC-USDC");
        const numeric=(v)=>typeof v==="string" && /^-?[0-9]+(?:\\.[0-9]+)?$/.test(v);
        if(verifiedBrowserFill && product?.fill_count===1 &&
          numeric(product.fees_paid)&&Number(product.fees_paid)>0 &&
          numeric(product.position_qty)&&Number(product.position_qty)>0 &&
          numeric(product.cash)&&numeric(product.cost_basis) &&
          numeric(product.realized_pnl) && product.quote_currency==="USDC" &&
          /^[a-f0-9]{64}$/.test(report.snapshot_seal||"") &&
          report.original_risk_proof_verified===true){
          send("w03_browser_fill_sealed_fifo_fees_pnl");
          const button=document.getElementById("paperSessionArchive");
          if(button){
            button.click();
            try{
              await waiting(()=>{
                const displayed=document.getElementById("paperSessionStatus")?.textContent||"";
                return displayed.includes("COLD ACCOUNT") &&
                  displayed.includes("fees ") && displayed.includes("(1 fills)");
              },8000);
              send("w03_browser_account_visible_in_ui");
            }catch(_){send("w03_account_ui_not_visible");}
          }
        } else {
          send("w03_browser_sealed_account_fill_missing");
        }
      }
    }else{send("w03_archive_unavailable");}
  }
  run().catch(()=>send("w03_witness_exception"));
})();
