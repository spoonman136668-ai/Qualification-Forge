//go:build w122_public_matches_heartbeat_probe

package tickchart

// W122 is one bounded read-only first-use proof of a genuine public 100T
// Coinbase Exchange matches+heartbeat bar. It never trades, sends account
// requests, reads credentials or persists market history. Production code is
// immutable and this test exists only in a disposable QForge checkout.
import (
 "context"
 "errors"
 "fmt"
 "os"
 "strconv"
 "testing"
 "time"
)

var w122Witness = errors.New("W122_VERIFIED_PUBLIC_SESSION_BAR")

func TestW122GenuinePublicSessionHundredTrades(t *testing.T){
 if os.Getenv("W122_PUBLIC_READONLY_ONESHOT")!="1"||
    os.Getenv("KTRADE_LIVE_TRADING")!="false"||
    os.Getenv("KTRADE_CI_LIVE_AUTHORITY")!="0"||
    os.Getenv("KTRADE_CI_PROMOTION_ALLOWED")!="0"||
    os.Getenv("KTRADE_PAPER_SESSION_ROOT")!=""||
    os.Getenv("KTRADE_PAPER_CUSTODY_REVIEW_ROOT")!="" {
   t.Fatal("W122_PUBLIC_FINANCIAL_GUARD_REFUSED")
 }
 ctx,cancel:=context.WithTimeout(context.Background(),55*time.Second)
 defer cancel()
 observed:=0
 started:=time.Now()
 err:=RunCoinbaseMatchesHeartbeat(ctx,"BTC-USD",100,func(b Bar)error{
   if b.ProductID!="BTC-USD"||b.TradeCount!=100||
      b.FirstTradeID==""||b.LastTradeID==""||
      b.Start.IsZero()||b.End.IsZero()||b.End.Before(b.Start)||
      b.Open==""||b.High==""||b.Low==""||b.Close==""||b.Volume==""{
     return fmt.Errorf("%w: malformed completed bar",ErrCoverage)
   }
   first,a:=strconv.ParseUint(b.FirstTradeID,10,64)
   last,z:=strconv.ParseUint(b.LastTradeID,10,64)
   if a!=nil||z!=nil||first==0||last<first||last-first!=99{
     return fmt.Errorf("%w: incomplete execution id window",ErrCoverage)
   }
   observed++
   return w122Witness
 })
 elapsed:=time.Since(started).Round(time.Millisecond)
 if errors.Is(err,w122Witness)&&observed==1{
   t.Logf("W122_REAL_PUBLIC_MATCHES_HEARTBEAT_100T=PASS;source=W121;product=BTC-USD;count=100;complete_bars=1;elapsed=%s;heartbeats=REQUIRED;gap_free=TRUE;orders=ZERO;credentials=ZERO;retries=ZERO",elapsed)
   return
 }
 classification:="UNKNOWN_OR_DISCONNECT"
 switch{
 case errors.Is(err,ErrCoverage):classification="COVERAGE_OR_FORMAT_REFUSED"
 case errors.Is(err,ErrTrade):classification="INVALID_EXECUTION_REFUSED"
 case errors.Is(err,ErrExchangeReadOnly):classification="WEBSOCKET_UNAVAILABLE_OR_CLOSED"
 case errors.Is(err,context.DeadlineExceeded):classification="NO_CERTIFIED_BAR_WITHIN_BUDGET"
 }
 t.Fatalf("W122_PUBLIC_FEED_RESULT=UNVERIFIED;class=%s;complete_bars=%d;elapsed=%s;orders=ZERO;retries=ZERO",classification,observed,elapsed)
}
