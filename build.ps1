# Go compile the DLLs
Set-Location C:\github\dbatools
Push-Location ".\bin\projects\dbatools"
dotnet publish --framework net6.0 | Out-String -OutVariable build
dotnet publish --framework net462 | Out-String -OutVariable build
dotnet test --framework net462 --verbosity normal | Out-String -OutVariable test
dotnet test --framework net6.0 --verbosity normal | Out-String -OutVariable test
Pop-Location

# Remove all the SMO directories that the build created -- they are elsewhere in the project
#Get-ChildItem -Directory ".\bin\net462" | Remove-Item -Recurse -Confirm:$false
#Get-ChildItem -Directory ".\bin\net6.0" | Remove-Item -Recurse -Confirm:$false

# Remove all the SMO files that the build created -- they are elsewhere in the project
#Get-ChildItem ".\bin\net6.0" -Recurse -Exclude dbatools.* | Move-Item -Destination ".\bin\smo\coreclr" -Confirm:$false -Force
#Get-ChildItem ".\bin\net462" -Recurse -Exclude dbatools.* | Move-Item -Destination ".\bin\smo\" -Confirm:$false -Force
#Get-ChildItem ".\bin" -Recurse -Include dbatools.deps.json | Remove-Item -Confirm:$false

# Sign the DLLs, how cool -- Set-AuthenticodeSignature works on DLLs (and presumably Exes) too
<#$buffer = [IO.File]::ReadAllBytes(".\dbatools-code-signing-cert.pfx")
$certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::New($buffer, $password)
Get-ChildItem dbatools\dbatools.dll -Recurse | Set-AuthenticodeSignature -Certificate $certificate -TimestampServer http://timestamp.digicert.com
#>