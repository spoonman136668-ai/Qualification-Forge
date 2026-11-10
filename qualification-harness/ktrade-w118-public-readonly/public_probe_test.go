//go:build w118_public_readonly_probe

package tickchart

// One-shot public-data-only acceptance witness. This file is staged in an
// ephemeral QForge-hosted checkout, and is NOT part of KTRADE source or
// production tests. The only possible network operations are W117's fixed
// unauthenticated Exchange public-full WS and one same-product L3 GET.
// No trading API, broker credentials, account data, user installation,
// persistent state, loop, retry or paid endpoint is permitted here.
import (
 "context"
 "errors"
 "fmt"
 "os"
 "testing"
 "time"
)

var w118BarWitnessComplete = errors.New("W118_PUBLIC_COMPLETED_BAR")

func TestW118PublicCoinbaseFullReadOnlyHundredTrades(t *testing.T) {
 if os.Getenv("KTRADE_LIVE_TRADING")!="false"||
    os.Getenv("KTRADE_CI_LIVE_AUTHORITY")!="0"||
    os.Getenv("KTRADE_CI_PROMOTION_ALLOWED")!="0"||
    os.Getenv("KTRADE_PAPER_SESSION_ROOT")!=""||
    os.Getenv("KTRADE_PAPER_CUSTODY_REVIEW_ROOT")!=""||
    os.Getenv("W118_PUBLIC_MARKET_DATA_ONLY")!="1" {
   t.Fatal("W118_PUBLIC_MARKET_PROBE_GUARD_FAILED")
 }
 ctx,cancel:=context.WithTimeout(context.Background(),55*time.Second)
 defer cancel()
 observed:=0
 started:=time.Now()
 err:=RunCoinbaseExchangeFull(ctx,"BTC-USD",100,func(bar Bar)error{
   if bar.ProductID!="BTC-USD"||bar.TradeCount!=100||
      bar.FirstTradeID==""||bar.LastTradeID==""||
      bar.Start.IsZero()||bar.End.IsZero()||bar.End.Before(bar.Start)||
      bar.Open==""||bar.Close==""||bar.High==""||bar.Low==""||bar.Volume==""{
      return fmt.Errorf("%w: invalid finalized bar boundary",ErrCoverage)
   }
   observed++
   return w118BarWitnessComplete
 })
 elapsed:=time.Since(started).Round(time.Millisecond)
 if errors.Is(err,w118BarWitnessComplete) && observed==1 {
   t.Logf("W118_PUBLIC_MARKET_TLS_WS_L3_SESSION_100T=PASS;duration=%s;product=BTC-USD;completed_bars=1;trade_count=100;execution_mode=READ_ONLY;auth=NONE;orders=ZERO;retries=ZERO",elapsed)
   return
 }
 // One bounded attempt only: no auto-reconnect to disguise coverage failures.
 classification:="SOURCE_REJECTED_OR_NETWORK_UNVERIFIED"
 switch{
 case errors.Is(err,context.DeadlineExceeded):
   classification="NO_CERTIFIED_BAR_WITHIN_BUDGET"
 case errors.Is(err,ErrCoverage):
   classification="SEQUENCE_OR_SNAPSHOT_COVERAGE_REFUSED"
 case errors.Is(err,ErrTrade):
   classification="INVALID_EXCHANGE_TRADE_REFUSED"
 case errors.Is(err,ErrExchangeReadOnly):
   classification="PUBLIC_FEED_OR_TLS_UNAVAILABLE"
 }
 t.Fatalf("W118_PUBLIC_MARKET_RESULT=UNVERIFIED;class=%s;elapsed=%s;completed_bars=%d;orders=ZERO;retries=ZERO",classification,elapsed,observed)
}
