if ($env:VSO_MODULE_LAB_AUTHORIZED -ne '1') { throw 'Use Invoke-LabTests.ps1 in an authorized disposable VM.' }
InModuleScope VSO {
    BeforeAll {
        $script:ctx=New-VSOContext en -Quiet
        $script:uriImplementation=${function:Assert-VSOUri}
        if(-not('VSOLab.FixtureServer' -as [type])){
            Add-Type @'
using System;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
namespace VSOLab {
 public sealed class FixtureServer : IDisposable {
  readonly TcpListener listener;readonly Thread thread;public string Uri {get;private set;}
  public FixtureServer(string headers,byte[] body){
   listener=new TcpListener(IPAddress.Loopback,0);listener.Start();Uri="http://127.0.0.1:"+((IPEndPoint)listener.LocalEndpoint).Port+"/fixture";
   thread=new Thread(delegate(){try{using(var client=listener.AcceptTcpClient()){client.ReceiveTimeout=5000;using(var stream=client.GetStream()){int n=0,last=0;while(n++<16384){int b=stream.ReadByte();if(b<0)break;last=((last<<8)|b);if(last==0x0d0a0d0a)break;}var h=Encoding.ASCII.GetBytes(headers);stream.Write(h,0,h.Length);stream.Flush();if(body.Length>0){stream.Write(body,0,body.Length);stream.Flush();}}}}catch(System.IO.IOException){}catch(SocketException){}catch(ObjectDisposedException){}});
   thread.IsBackground=true;thread.Start();
  }
  public void Dispose(){listener.Stop();thread.Join(2000);}
 }
}
'@ -ErrorAction Stop
        }
    }
    Describe 'Actual HttpClient against bounded loopback failure fixtures' {
        BeforeEach {
            # Permit this exact fixture endpoint only. All other URLs and redirects
            # still pass through the unchanged production allowlist implementation.
            Mock Assert-VSOUri {
                param([uri]$Uri,$Context,[switch]$Redirect)
                if($Uri.Host -ceq '127.0.0.1' -and $Uri.Port -eq ([uri]$script:server.Uri).Port){return}
                & $script:uriImplementation $Uri $Context -Redirect:$Redirect
            }
        }
        AfterEach {if($script:server){$script:server.Dispose();$script:server=$null}}
        It 'rejects a real disconnected response with a truncated declared body' {
            $body=[Text.Encoding]::ASCII.GetBytes(('x'*100))
            $script:server=[VSOLab.FixtureServer]::new("HTTP/1.1 200 OK`r`nContent-Length: 200`r`nConnection: close`r`n`r`n",$body)
            $out=Join-Path $TestDrive 'partial.bin'
            {Invoke-VSOHttp ([uri]$script:server.Uri) $script:ctx -OutFile $out -ExpectedSize 200 -MaximumBytes 1024}|Should -Throw
            if(Test-Path -LiteralPath $out){(Get-Item -LiteralPath $out).Length|Should -BeLessOrEqual 100}
        }
        It 'rejects an excessive response length before creating its output file' {
            $script:server=[VSOLab.FixtureServer]::new("HTTP/1.1 200 OK`r`nContent-Length: 4096`r`nConnection: close`r`n`r`n",[byte[]]@())
            $out=Join-Path $TestDrive 'oversize.bin'
            {Invoke-VSOHttp ([uri]$script:server.Uri) $script:ctx -OutFile $out -MaximumBytes 1024}|Should -Throw
            Test-Path -LiteralPath $out|Should -BeFalse
        }
        It 'enforces the streamed limit on a real chunked response without Content-Length' {
            $body=[Text.Encoding]::ASCII.GetBytes("1000`r`n"+('x'*4096)+"`r`n0`r`n`r`n")
            $script:server=[VSOLab.FixtureServer]::new("HTTP/1.1 200 OK`r`nTransfer-Encoding: chunked`r`nConnection: close`r`n`r`n",$body)
            $out=Join-Path $TestDrive 'chunked.bin'
            {Invoke-VSOHttp ([uri]$script:server.Uri) $script:ctx -OutFile $out -MaximumBytes 1024}|Should -Throw
            if(Test-Path -LiteralPath $out){(Get-Item -LiteralPath $out).Length|Should -BeLessOrEqual 1024}
        }
        It 'rejects an unsafe redirect received from a real fixture socket' {
            $script:server=[VSOLab.FixtureServer]::new("HTTP/1.1 302 Found`r`nLocation: http://example.invalid/payload`r`nContent-Length: 0`r`nConnection: close`r`n`r`n",[byte[]]@())
            {Invoke-VSOHttp ([uri]$script:server.Uri) $script:ctx}|Should -Throw
        }
    }
}
