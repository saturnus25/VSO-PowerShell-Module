function Assert-VSOUri {
    param([uri]$Uri, $Context, [switch]$Redirect)
    if ($Uri.Scheme -ne 'https' -or $Uri.UserInfo -or -not $Uri.IsDefaultPort) { Throw-VSOError $Context Network @('URL') }
    $valid=($Uri.Host -eq 'api.github.com' -and $Uri.AbsolutePath.StartsWith('/repos/saturnus25/VSO/releases',[StringComparison]::Ordinal)) -or ($Uri.Host -eq 'github.com' -and $Uri.AbsolutePath.StartsWith('/saturnus25/VSO/releases/download/',[StringComparison]::Ordinal))
    if ($Redirect -and $Uri.Host -in @('release-assets.githubusercontent.com','objects.githubusercontent.com','github-releases.githubusercontent.com')) { $valid=$true }
    if (-not $valid) { Throw-VSOError $Context Network @('untrusted URL') }
}

function Assert-VSOHttpStatus {
    param($Response, [uri]$Uri, $Context)
    $code=[int]$Response.StatusCode
    if ($code -eq 404) { Throw-VSOError $Context ReleaseMissing @($Uri.AbsolutePath) }
    if ($code -eq 429 -or ($code -eq 403 -and $Response.Headers.Contains('X-RateLimit-Remaining') -and (@($Response.Headers.GetValues('X-RateLimit-Remaining'))[0] -eq '0'))) {
        $reset=if ($Response.Headers.Contains('X-RateLimit-Reset')) { @($Response.Headers.GetValues('X-RateLimit-Reset'))[0] } else { 'Retry-After' }
        Throw-VSOError $Context RateLimit @($reset)
    }
    if (-not $Response.IsSuccessStatusCode) { Throw-VSOError $Context Network @('HTTP '+$code) }
}

function Invoke-VSOHttp {
    param([uri]$Uri, $Context, [string]$OutFile, [long]$ExpectedSize = -1, [long]$MaximumBytes = 8388608)
    Assert-VSOUri $Uri $Context
    Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
    $handler=[Net.Http.HttpClientHandler]::new(); $handler.AllowAutoRedirect=$false
    $handler.SslProtocols=[Security.Authentication.SslProtocols]::Tls12
    $client=[Net.Http.HttpClient]::new($handler); $client.Timeout=[TimeSpan]::FromMinutes(10)
    $cancellation=[Threading.CancellationTokenSource]::new([TimeSpan]::FromMinutes(10))
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('VSO/1.0.0')
    $client.DefaultRequestHeaders.Accept.ParseAdd('application/vnd.github+json')
    $response=$null; $stream=$null; $output=$null
    try {
        for ($hop=0; $hop -le 5; $hop++) {
            $response=$client.GetAsync($Uri,[Net.Http.HttpCompletionOption]::ResponseHeadersRead,$cancellation.Token).GetAwaiter().GetResult()
            $code=[int]$response.StatusCode
            if ($code -in @(301,302,303,307,308)) {
                if ($hop -eq 5 -or $null -eq $response.Headers.Location) { Throw-VSOError $Context Network @('redirect limit') }
                $Uri=[uri]::new($Uri,$response.Headers.Location); Assert-VSOUri $Uri $Context -Redirect
                $response.Dispose(); $response=$null; continue
            }
            break
        }
        Assert-VSOHttpStatus $response $Uri $Context
        $length=$response.Content.Headers.ContentLength
        if (($null -ne $length -and $length -gt $MaximumBytes) -or ($ExpectedSize -ge 0 -and $null -ne $length -and $length -ne $ExpectedSize)) { Throw-VSOError $Context Integrity @('response length') }
        $stream=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        if ($stream.CanTimeout) { $stream.ReadTimeout=60000 }
        if ($OutFile) {
            Assert-VSONoReparse $OutFile $Context
            $output=[IO.FileStream]::new($OutFile,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        } else { $output=[IO.MemoryStream]::new() }
        $buffer=[byte[]]::new(65536); [long]$received=0; $watch=[Diagnostics.Stopwatch]::StartNew()
        while (($read=$stream.ReadAsync($buffer,0,$buffer.Length,$cancellation.Token).GetAwaiter().GetResult()) -gt 0) {
            $received+=$read
            if ($received -gt $MaximumBytes -or ($ExpectedSize -ge 0 -and $received -gt $ExpectedSize)) { Throw-VSOError $Context Integrity @('download size limit') }
            $output.Write($buffer,0,$read)
            if ($OutFile -and $watch.ElapsedMilliseconds -ge 200) { Write-VSOProgress $Context Download $received $ExpectedSize; $watch.Restart() }
        }
        if (($ExpectedSize -ge 0 -and $received -ne $ExpectedSize) -or ($null -ne $length -and $received -ne $length)) { Throw-VSOError $Context Integrity @('interrupted download') }
        if (-not $OutFile) { return [Text.Encoding]::UTF8.GetString($output.ToArray()) }
    } catch {
        if ($_.FullyQualifiedErrorId -like 'VSO.*') { throw }
        Throw-VSOError $Context Network @($_.Exception.Message) $_.Exception
    } finally {
        if ($output) { $output.Dispose() }; if ($stream) { $stream.Dispose() }; if ($response) { $response.Dispose() }; $client.Dispose(); $cancellation.Dispose()
        Write-VSOProgress $Context Download -Completed
    }
}

function Get-VSORelease {
    param($Context, [string]$Version, [switch]$Prerelease, [string]$AssetName)
    Write-VSOProgress $Context Query
    try {
        $base='https://api.github.com/repos/saturnus25/VSO/releases'
        if (-not $Version -and -not $Prerelease) { $release=(Invoke-VSOHttp ($base+'/latest') $Context | ConvertFrom-Json -ErrorAction Stop) }
        else {
            $wanted=if ($Version) { (ConvertTo-VSOVersion $Version $Context).Text } else { $null }
            $release=$null
            for ($page=1; $page -le 20; $page++) {
                $batch=@(Invoke-VSOHttp ($base+'?per_page=100&page='+$page) $Context | ConvertFrom-Json -ErrorAction Stop)
                # ConvertFrom-Json in 5.1 may emit the array as a single pipeline object.
                $batch=@($batch | ForEach-Object { $_ })
                foreach ($candidate in $batch) {
                    if (Get-VSOProperty $candidate draft $true) { continue }
                    $tag=[string](Get-VSOProperty $candidate tag_name '')
                    try { $candidateVersion=(ConvertTo-VSOVersion $tag $Context).Text } catch { continue }
                    if ($wanted -and $candidateVersion -ne $wanted) { continue }
                    if (-not $Prerelease -and (Get-VSOProperty $candidate prerelease $false)) { if ($wanted) { Throw-VSOError $Context Prerelease }; continue }
                    if ($wanted) { $release=$candidate; break }
                    if ($null -eq $release -or (Compare-VSOVersion $candidateVersion ([string]$release.tag_name) $Context) -gt 0) { $release=$candidate }
                }
                if ($wanted -and $release) { break }
                if ($batch.Count -lt 100) { break }
                if ($page -eq 20) { Throw-VSOError $Context Network @('release pagination limit') }
            }
        }
        if (-not $release -or (Get-VSOProperty $release draft $true)) { Throw-VSOError $Context ReleaseMissing @($Version) }
        $versionText=(ConvertTo-VSOVersion ([string]$release.tag_name) $Context).Text
        if (-not $Prerelease -and ((Get-VSOProperty $release prerelease $false) -or $versionText.Contains('-'))) { Throw-VSOError $Context Prerelease }
        $assets=@($release.assets | Where-Object { $_.name -match '(?i)\.zip$' -and (Get-VSOProperty $_ state '') -eq 'uploaded' })
        if ($AssetName) { $assets=@($assets | Where-Object name -CEQ $AssetName) }
        if ($assets.Count -ne 1) { Throw-VSOError $Context Asset }
        $asset=$assets[0]; Assert-VSOUri ([uri]$asset.browser_download_url) $Context
        if ([long]$asset.size -le 0 -or [long]$asset.size -gt 134217728) { Throw-VSOError $Context Archive @('asset size') }
        $digest=[string](Get-VSOProperty $asset digest '')
        $hash=$null; $method=$null
        if ($digest -match '^sha256:([a-fA-F0-9]{64})$') { $hash=$Matches[1].ToLowerInvariant(); $method='GitHubAssetDigest' }
        else {
            $sidecars=@($release.assets | Where-Object { $_.name -ceq ($asset.name+'.sha256') -or $_.name -ceq 'SHA256SUMS.txt' })
            foreach ($sidecar in $sidecars) {
                if ([long]$sidecar.size -gt 1048576) { Throw-VSOError $Context Integrity @('checksum size') }
                $text=Invoke-VSOHttp ([uri]$sidecar.browser_download_url) $Context -MaximumBytes 1048576
                foreach ($line in ($text -split '\r?\n')) {
                    if ($line -match '^([a-fA-F0-9]{64})[ \t]+\*?(.+)$' -and $Matches[2] -ceq $asset.name) {
                        if ($hash -and $hash -cne $Matches[1].ToLowerInvariant()) { Throw-VSOError $Context Integrity @('conflicting checksums') }
                        $hash=$Matches[1].ToLowerInvariant(); $method='OfficialChecksum'
                    }
                }
            }
        }
        if (-not $hash) { Throw-VSOError $Context NoDigest }
        return [pscustomobject]@{ Version=$versionText; Tag=[string]$release.tag_name; ReleaseUri=[string]$release.html_url; AssetName=[string]$asset.name; AssetUri=[string]$asset.browser_download_url; Size=[long]$asset.size; Sha256=$hash; IntegrityMethod=$method; Prerelease=[bool]$release.prerelease }
    } finally { Write-VSOProgress $Context Query -Completed }
}
