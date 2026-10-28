# Independent source-bound OS raster oracle. No inspector, JavaScript execution,
# DOM access, canvas extraction or runtime hooks. LWC 4.1.0 source contracts:
# time-scale.ts indexToCoordinate + fitContent; price-scale.ts
# _logicalToCoordinate; default scaleMargins top .2/bottom .1; time-axis
# optimalHeight 28 CSS px; chart size rounded down to even CSS dimensions.
function Find-W32ERegion([object]$proc,[string]$name){
  $root=[System.Windows.Automation.AutomationElement]::FromHandle($proc.MainWindowHandle)
  $all=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
  $matches=@()
  foreach($el in $all){try{if($el.Current.Name -ceq $name -and !$el.Current.IsOffscreen -and !$el.Current.BoundingRectangle.IsEmpty){$matches+=,$el}}catch{}}
  if($matches.Count -ne 1){throw ('W32E_P1C_REGION_AMBIGUOUS_'+$name)}
  return $matches[0].Current.BoundingRectangle
}
function Capture-W32EOS([object]$proc,[string]$phase){
  $pine=Find-W32ERegion $proc 'Pine indicator pane'
  $price=Find-W32ERegion $proc 'Price chart drawing surface'
  $scale=[W32EDpi]::GetDpiForWindow($proc.MainWindowHandle)/96.0
  if($scale -lt .75 -or $scale -gt 2.5){throw 'W32E_P1C_DPI_UNSUPPORTED'}
  $sizeButton=Wait-W32EUI $proc 'Expand Pine indicator pane'
  $headerBottom=$sizeButton.Current.BoundingRectangle.Bottom
  $chartTop=$headerBottom+3*$scale-$pine.Top
  if($chartTop -lt 25*$scale -or $chartTop -gt 35*$scale){throw 'W32E_P1C_HEADER_GEOMETRY_UNSUPPORTED'}
  $volumeTop=[int][Math]::Round($price.Bottom+6*$scale)
  $volumeHeight=[int][Math]::Round($pine.Top-$volumeTop)
  $volume=[pscustomobject]@{Left=$price.Left;Top=$volumeTop;Width=$price.Width;Height=$volumeHeight}
  $root=[System.Windows.Automation.AutomationElement]::FromHandle($proc.MainWindowHandle).Current.BoundingRectangle
  [void][W32ENativeInput]::SetForegroundWindow($proc.MainWindowHandle)
  Start-Sleep -Milliseconds 250
  if([W32ENativeInput]::GetForegroundWindow() -ne $proc.MainWindowHandle){throw 'W32E_P1C_CAPTURE_FOREIGN_FOCUS'}
  $result=@{scale=$scale;phase=$phase;chart_top=$chartTop}
  foreach($kind in @('pine','volume')){
    $r=if($kind -ceq 'pine'){$pine}else{$volume}
    $left=[int][Math]::Round($r.Left);$top=[int][Math]::Round($r.Top)
    $w=[int][Math]::Floor($r.Width);$h=[int][Math]::Floor($r.Height)
    if($w -lt 240 -or $h -lt 35 -or $left -lt $root.Left -or $top -lt $root.Top -or $left+$w -gt $root.Right+1 -or $top+$h -gt $root.Bottom+1){throw 'W32E_P1C_RASTER_RECT_NOT_OWNED'}
    $bmp=[Drawing.Bitmap]::new($w,$h);$gfx=[Drawing.Graphics]::FromImage($bmp)
    try{
      $gfx.CopyFromScreen($left,$top,0,0,$bmp.Size,[Drawing.CopyPixelOperation]::SourceCopy)
      $mem=[IO.MemoryStream]::new();$sha=[Security.Cryptography.SHA256]::Create()
      try{$bmp.Save($mem,[Drawing.Imaging.ImageFormat]::Png);$hash=[Convert]::ToHexString($sha.ComputeHash($mem.ToArray())).ToLowerInvariant()}finally{$mem.Dispose();$sha.Dispose()}
      $fuchsia=[Collections.Generic.List[object]]::new();$teal=[Collections.Generic.List[object]]::new()
      $columns=New-Object int[] $w;$rows=New-Object int[] $h
      for($y=0;$y -lt $h;$y++){for($x=0;$x -lt $w;$x++){
        $px=$bmp.GetPixel($x,$y)
        if($px.R -ge 170 -and $px.B -ge 140 -and $px.G -lt 130 -and ($px.R+$px.B-2*$px.G) -ge 200){$fuchsia.Add([pscustomobject]@{x=$x;y=$y})}
        if($px.G-$px.R -ge 40 -and $px.B-$px.R -ge 25 -and $px.G -gt 65 -and $px.R -lt 80){$teal.Add([pscustomobject]@{x=$x;y=$y})}
        if($px.R -eq 42 -and $px.G -eq 46 -and $px.B -eq 57){$columns[$x]++;$rows[$y]++}
      }}
      $result[$kind]=[pscustomobject]@{width=$w;height=$h;hash=$hash;fuchsia=$fuchsia;teal=$teal;border_columns=$columns;border_rows=$rows;left=$left;top=$top}
    }finally{$gfx.Dispose();$bmp.Dispose()}
  }
  return [pscustomobject]$result
}
function Check-W32EOSRaster([object]$before,[object]$after){
  if($before.scale -ne $after.scale){throw 'W32E_P1C_DPI_CHANGED'}
  foreach($kind in @('pine','volume')){foreach($key in @('left','top','width','height')){if($before.$kind.$key -ne $after.$kind.$key){throw ('W32E_P1C_GEOMETRY_CHANGED_'+$kind+'_'+$key)}}}
  if($before.volume.hash -cne $after.volume.hash){throw ('W32E_P1C_VOLUME_RASTER_CHANGED_before_'+$before.volume.hash+'_after_'+$after.volume.hash)}
  if($before.pine.fuchsia.Count -ne 0 -or $after.pine.fuchsia.Count -lt 80 -or $after.volume.fuchsia.Count -ne 0){throw 'W32E_P1C_PLOT_COLOR_ISOLATION_FAILED'}
  $scale=$after.scale;$pane=$after.pine
  # UIA independently anchors pane and header button. The pinned CSS has
  # 3px bottom padding; LWC uses even chart height and a 28px time axis.
  $chartTop=$after.chart_top
  $cssChartHeight=[int][Math]::Floor(($pane.height-$chartTop)/$scale)
  $cssChartHeight-=$cssChartHeight%2
  $plotHeight=$cssChartHeight-28
  if($plotHeight -lt 35){throw 'W32E_P1C_PLOT_TOO_SHORT'}
  # Find the native right-scale border using exact neutral border pixels,
  # independently of fuchsia output. Require a unique, near-continuous edge.
  $edges=@()
  for($x=[int](100*$scale);$x -lt $pane.width-10*$scale;$x++){
    # The default last-value axis label covers part of the neutral border.
    if($pane.border_columns[$x] -ge $plotHeight*$scale*.60){$edges+=,$x}
  }
  if($edges.Count -lt 1 -or $edges.Count -gt [Math]::Ceiling(2*$scale)){throw ('W32E_P1C_PRICE_AXIS_BORDER_AMBIGUOUS_'+($edges -join ','))}
  $plotWidth=[double]$edges[0]/$scale
  $axisY=[int][Math]::Round($chartTop+$plotHeight*$scale)
  $axisFound=$false
  for($y=$axisY-1;$y -le $axisY+1;$y++){if($pane.border_rows[$y] -ge $plotWidth*$scale*.85){$axisFound=$true}}
  if(!$axisFound){throw ('W32E_P1C_TIME_AXIS_GEOMETRY_UNCONFIRMED_y_'+$axisY)}
  # Thirty finite timestamps including the two whitespace warm-up positions.
  # Expected values come independently from the 30 synthetic Go OHLCV bars.
  $radius=[int][Math]::Ceiling(2*$scale)
  $lastPriceY=$chartTop+.2*$plotHeight*$scale
  $points=@();$hits=0;$negative=0;$errors=@()
  for($i=2;$i -lt 30;$i++){
    $x=($plotWidth-(29-$i+.5)*($plotWidth/30)-1)*$scale
    $value=99+$i
    $y=$chartTop+($plotHeight-1-(.1*$plotHeight+(.7*$plotHeight-1)*($value-101)/27))*$scale
    $local=@($pane.fuchsia|Where-Object {[Math]::Abs($_.x-$x) -le $radius -and [Math]::Abs($_.y-$y) -le $radius})
    if($local.Count -gt 0){$hits++;$errors+=($local|ForEach-Object {[Math]::Sqrt([Math]::Pow($_.x-$x,2)+[Math]::Pow($_.y-$y,2))}|Measure-Object -Minimum).Minimum}
    $wrongY=if($y+20*$scale -lt $chartTop+$plotHeight*$scale){$y+20*$scale}else{$y-20*$scale}
    if([Math]::Abs($wrongY-$lastPriceY) -le 2*$radius){$wrongY=$y+20*$scale}
    $wrong=@($pane.fuchsia|Where-Object {[Math]::Abs($_.x-$x) -le $radius -and [Math]::Abs($_.y-$wrongY) -le $radius})
    if($wrong.Count -gt 0){$negative++}
    $points+=@{bar=$i;expected_sma=$value;x=$x;y=$y;matched=$local.Count -gt 0;wrong_y_matched=$wrong.Count -gt 0}
  }
  $warmup=0
  for($i=0;$i -lt 2;$i++){
    $x=($plotWidth-(29-$i+.5)*($plotWidth/30)-1)*$scale
    # LWC defaults include a dashed horizontal last-price line. Its known
    # row is unrelated to the two NA samples and is excluded only here.
    $warm=@($pane.fuchsia|Where-Object {[Math]::Abs($_.x-$x) -le $radius -and $_.y -gt $chartTop -and $_.y -lt $chartTop+$plotHeight*$scale -and [Math]::Abs($_.y-$lastPriceY) -gt $radius})
    if($warm.Count -eq 0){$warmup++}
  }
  Write-Output ('W32E_P1C_NATIVE_POINTS='+($points|ConvertTo-Json -Compress))
  Write-Output ('W32E_P1C_NATIVE_GEOMETRY='+(@{dpi_scale=$scale;plot_width_css=$plotWidth;plot_height_css=$plotHeight;chart_top_physical=$chartTop;price_axis_columns=$edges;time_axis_y=$axisY;warmup_positions_blank=$warmup}|ConvertTo-Json -Compress))
  if($hits -ne 28 -or $negative -ne 0 -or $warmup -ne 2){throw ('W32E_P1C_POINT_RASTER_FAILED_hits_'+$hits+'_negative_'+$negative+'_warmup_'+$warmup)}
  # Independently identify all 30 native volume histogram bars from their
  # teal pixels; this is also independent of the Pine line and its scale.
  $volumeBars=0
  for($i=0;$i -lt 30;$i++){
    $x=($after.volume.width-(29-$i+.5)*($after.volume.width/30)-1)
    $near=@($after.volume.teal|Where-Object {[Math]::Abs($_.x-$x) -le $radius})
    if($near.Count -gt 0){$volumeBars++}
  }
  if($volumeBars -ne 30){throw ('W32E_P1C_NATIVE_VOLUME_BAR_COUNT_'+$volumeBars)}
  Write-Output ('W32E_P1C_EXACT_RASTER_PROOF='+(@{source='1c399965d8ab88a42e25f9997e0db15dec15e6b0';mapped_points=$hits;displaced_negative_hits=$negative;warmup_positions_blank=$warmup;max_nearest_pixel_distance=($errors|Measure-Object -Maximum).Maximum;physical_tolerance=$radius;scale=$scale;baseline_pine_pixels=$before.pine.fuchsia.Count;applied_pine_pixels=$after.pine.fuchsia.Count;volume_pine_pixels=$after.volume.fuchsia.Count;native_volume_bars_unchanged=$volumeBars;volume_png_before=$before.volume.hash;volume_png_after=$after.volume.hash;pine_png_sha256=$after.pine.hash;pine_width=$pane.width;pine_height=$pane.height;oracle='independent pinned LWC 4.1.0 formulas with OS UIA DPI and neutral axis-border geometry';input='Win32/UIA/clipboard';capture='Windows Graphics.CopyFromScreen';browser_inspector=$false;runtime_javascript=$false}|ConvertTo-Json -Compress))
  Write-Output '::notice::W32E_P1C_NATIVE_28_POINT_COORDINATES_AND_VOLUME_RASTER_IDENTITY=PASS'
}
