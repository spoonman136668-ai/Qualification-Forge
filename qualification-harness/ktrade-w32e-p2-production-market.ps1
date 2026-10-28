function Assert-W32EProductionBars([object]$response){
  if($response.success -ne $true -or $response.source -cne 'coinbase_advanced_public_rest' -or $response.finalized -ne $true -or $response.stale -ne $false){throw 'W32E_P2_CURRENT_FINALIZED_SOURCE_REQUIRED'}
  $rows=@($response.candles)
  if($rows.Count -lt 250 -or $rows.Count -gt 300){throw ('W32E_P2_CURRENT_HISTORY_COUNT_'+$rows.Count)}
  $now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $last=0L
  foreach($row in $rows){
    $t=[long]$row.time
    if($t -le $last -or $t%60 -ne 0 -or $t+62 -gt $now -or $row.product_id -cne 'BTC-USDC'){throw 'W32E_P2_BAR_IDENTITY_OR_FINALITY_INVALID'}
    foreach($value in @($row.open,$row.high,$row.low,$row.close,$row.volume)){
      if($null -eq $value -or [double]::IsNaN([double]$value) -or [double]::IsInfinity([double]$value)){throw 'W32E_P2_NONFINITE_BAR'}
    }
    if($row.low -le 0 -or $row.high -lt $row.low -or $row.open -lt $row.low -or $row.open -gt $row.high -or $row.close -lt $row.low -or $row.close -gt $row.high -or $row.volume -lt 0){throw 'W32E_P2_OHLCV_INCONSISTENT'}
    $last=$t
  }
  $age=$now-($last+60)
  if($age -lt 2 -or $age -gt 120){throw ('W32E_P2_CURRENT_FINALIZED_AGE_'+$age)}
  $reported=[DateTimeOffset]::Parse($response.last_finalized_at).ToUnixTimeSeconds()
  if($reported -ne $last+60){throw 'W32E_P2_FINALIZED_METADATA_DIFFERS'}
  Write-Host ('W32E_P2_CURRENT_SOURCE_PROOF='+(@{rows=$rows.Count;product='BTC-USDC';timeframe='1m';source=$response.source;first_bar=$rows[0].time;last_bar=$last;last_close_age_seconds=$age;last_close=$rows[-1].close;last_volume=$rows[-1].volume;finalized=$response.finalized;stale=$response.stale}|ConvertTo-Json -Compress))
}
function Assert-W32EProductionPine([object]$overlay){
  $rows=@($overlay.candles)
  if(!$overlay.success -or $rows.Count -lt 250 -or $rows.Count -gt 300 -or @($overlay.pane_model).Count -ne 1 -or $overlay.pane_model[0].overlay -ne $false -or @($overlay.pane_model[0].plots).Count -ne 1){throw 'W32E_P2_REAL_GO_PINE_MODEL_INVALID'}
  $values=@($overlay.pane_model[0].plots[0].values)
  if($values.Count -ne $rows.Count -or $null -ne $values[0] -or $null -ne $values[1]){throw 'W32E_P2_REAL_GO_PINE_NA_INVALID'}
  $maxError=0.0
  for($i=2;$i -lt $rows.Count;$i++){
    $mean=([double]$rows[$i-2].close+[double]$rows[$i-1].close+[double]$rows[$i].close)/3
    $error=[Math]::Abs([double]$values[$i]-$mean)
    if($null -eq $values[$i] -or [double]::IsNaN([double]$values[$i]) -or [double]::IsInfinity([double]$values[$i]) -or $error -gt [Math]::Max(1e-7,[Math]::Abs($mean)*1e-11)){throw ('W32E_P2_ORIGINAL_GO_SMA_DIFFERS_'+$i)}
    $maxError=[Math]::Max($maxError,$error)
    if([long]$rows[$i].time -le [long]$rows[$i-1].time){throw 'W32E_P2_PINE_TIME_ORDER_INVALID'}
  }
  $last=[long]$rows[-1].time
  $age=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()-($last+60)
  if($age -lt 2 -or $age -gt 120){throw 'W32E_P2_PINE_MARKET_DATA_STALE_OR_UNFINALIZED'}
  Write-Host ('W32E_P2_ORIGINAL_GO_CURRENT_SMA_PROOF='+(@{rows=$rows.Count;computed=$values.Count-2;na_prefix=2;last_bar=$last;last_close_age_seconds=$age;max_absolute_sma_error=$maxError;last_sma=$values[-1];overlay=$false}|ConvertTo-Json -Compress))
}
function Assert-W32EIndependentProvider([object]$bars){
  $now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $url='https://api.coinbase.com/api/v3/brokerage/market/products/BTC-USDC/candles?start='+($now-304*60)+'&end='+$now+'&granularity=ONE_MINUTE&limit=350'
  $provider=Invoke-RestMethod -Uri $url -TimeoutSec 12 -MaximumRedirection 0 -Headers @{Accept='application/json';'User-Agent'='KTRADE-ReadOnly-Independent-Qualification/1.0'}
  $byTime=@{}
  foreach($row in @($provider.candles)){
    if($byTime.ContainsKey([string]$row.start)){throw 'W32E_P2_INDEPENDENT_PROVIDER_DUPLICATE'}
    $byTime[[string]$row.start]=$row
  }
  $matched=0
  foreach($row in @($bars.candles)){
    $raw=$byTime[[string]$row.time]
    if($null -eq $raw){throw 'W32E_P2_INDEPENDENT_PROVIDER_BAR_ABSENT'}
    foreach($name in @('open','high','low','close','volume')){
      $a=[double]$row.$name;$b=[double]::Parse([string]$raw.$name,[Globalization.CultureInfo]::InvariantCulture)
      if([Math]::Abs($a-$b) -gt [Math]::Max(1e-9,[Math]::Abs($a)*1e-11)){throw ('W32E_P2_INDEPENDENT_PROVIDER_OHLCV_DIFFERS_'+$name)}
    }
    $matched++
  }
  Write-Host ('W32E_P2_INDEPENDENT_PUBLIC_PROVIDER_PROOF='+(@{endpoint='https://api.coinbase.com/api/v3/brokerage/market/products/BTC-USDC/candles';matched_current_finalized_ohlcv_rows=$matched;raw_rows=@($provider.candles).Count;authentication='none';redirects_allowed=$false;transport='independent PowerShell HTTPS request, no source override'}|ConvertTo-Json -Compress))
}
function Check-W32EProductionRaster([object]$before,[object]$after,[object]$model){
  foreach($key in @('left','top','width','height')){if($before.pine.$key -ne $after.pine.$key){throw 'W32E_P2_PINE_GEOMETRY_CHANGED'}}
  if($before.pine.fuchsia.Count -ne 0 -or $after.pine.fuchsia.Count -lt 80 -or $after.volume.fuchsia.Count -ne 0){throw 'W32E_P2_CURRENT_NATIVE_PLOT_COLOR_ISOLATION_FAILED'}
  $values=@($model.pane_model[0].plots[0].values);$n=$values.Count
  $finite=@($values|Where-Object {$null -ne $_}|ForEach-Object {[double]$_})
  $min=[double](($finite|Measure-Object -Minimum).Minimum);$max=[double](($finite|Measure-Object -Maximum).Maximum)
  if($max -le $min){throw 'W32E_P2_REAL_MARKET_SMA_RANGE_DEGENERATE'}
  $s=$after.scale;$pane=$after.pine;$chartTop=$after.chart_top
  $cssHeight=[int][Math]::Floor(($pane.height-$chartTop)/$s);$cssHeight-=$cssHeight%2
  $plotHeight=$cssHeight-28;$edges=@()
  for($x=[int](100*$s);$x -lt $pane.width-10*$s;$x++){if($pane.border_columns[$x] -ge $plotHeight*$s*.60){$edges+=,$x}}
  if($edges.Count -lt 1 -or $edges.Count -gt [Math]::Ceiling(2*$s)){throw 'W32E_P2_NEUTRAL_PRICE_AXIS_AMBIGUOUS'}
  $plotWidth=$edges[0]/$s;$axisY=[int][Math]::Round($chartTop+$plotHeight*$s);$axisFound=$false
  for($y=$axisY-1;$y -le $axisY+1;$y++){if($pane.border_rows[$y] -ge $plotWidth*$s*.85){$axisFound=$true}}
  if(!$axisFound){throw 'W32E_P2_TIME_AXIS_GEOMETRY_UNCONFIRMED'}
  # Twenty-eight indices are selected before reading the target color pixels.
  # The source model supplies actual closed-candle values, never pixel fitting.
  $radius=[int][Math]::Ceiling(2*$s);$hits=0;$negative=0;$points=@()
  for($sample=0;$sample -lt 28;$sample++){
    $i=2+[int][Math]::Round(($n-3)*$sample/27)
    $x=($plotWidth-($n-1-$i+.5)*($plotWidth/$n)-1)*$s
    $v=[double]$values[$i]
    $y=$chartTop+($plotHeight-1-(.1*$plotHeight+(.7*$plotHeight-1)*($v-$min)/($max-$min)))*$s
    $near=@($pane.fuchsia|Where-Object {[Math]::Abs($_.x-$x) -le $radius -and [Math]::Abs($_.y-$y) -le $radius})
    if($near.Count -gt 0){$hits++}
    $wrongY=$chartTop+2*$s
    $wrong=@($pane.fuchsia|Where-Object {[Math]::Abs($_.x-$x) -le $radius -and [Math]::Abs($_.y-$wrongY) -le $radius})
    if($wrong.Count -gt 0){$negative++}
    $points+=@{bar=$i;time=$model.candles[$i].time;sma=$v;x=$x;y=$y;matched=$near.Count -gt 0;top_margin_negative_matched=$wrong.Count -gt 0}
  }
  Write-Output ('W32E_P2_REAL_MARKET_NATIVE_POINTS='+($points|ConvertTo-Json -Compress))
  if($hits -ne 28 -or $negative -ne 0){throw ('W32E_P2_CURRENT_NATIVE_POINT_MAP_hits_'+$hits+'_negative_'+$negative)}
  Write-Output ('W32E_P2_PRODUCTION_NATIVE_RASTER_PROOF='+(@{source='1c399965d8ab88a42e25f9997e0db15dec15e6b0';fixture_mode='none';rows=$n;sampled_points=$hits;negative_hits=$negative;physical_tolerance_per_axis=$radius;scale=$s;pine_width=$pane.width;pine_height=$pane.height;plot_width_css=$plotWidth;plot_height_css=$plotHeight;min_sma=$min;max_sma=$max;last_bar=$model.candles[-1].time;baseline_fuchsia=$before.pine.fuchsia.Count;applied_fuchsia=$pane.fuchsia.Count;volume_fuchsia=$after.volume.fuchsia.Count;pine_png_sha256=$pane.hash;baseline_volume_png=$before.volume.hash;applied_volume_png=$after.volume.hash;runtime_javascript=$false;browser_inspector=$false;source_transport_override=$false}|ConvertTo-Json -Compress))
  Write-Output '::notice::W32E_P2_UNTAGGED_PRODUCTION_CURRENT_MARKET_NATIVE_WEBVIEW2_PINE=PASS'
}
