# for PowerShell 3 zip file unblocking
# Thanks http://andyarismendi.blogspot.be/2012/02/unblocking-files-with-powershell.html
Add-Type -Namespace Win32 -Name PInvoke -MemberDefinition @"
        [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool DeleteFile(string name);
        public static int Win32DeleteFile(string filePath) {
            bool is_gone = DeleteFile(filePath); return Marshal.GetLastWin32Error();}
 
        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        static extern int GetFileAttributes(string lpFileName);
        public static bool Win32FileExists(string filePath) {return GetFileAttributes(filePath) != -1;}
"@

Remove-Module dbatools -ErrorAction SilentlyContinue
$url = 'https://github.com/ctrlbold/dbatools/archive/master.zip'
$path = Join-Path -Path (Split-Path -Path $profile) -ChildPath '\Modules\dbatools'
$temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
$zipfile = "$temp\sqltools.zip"

if (!(Test-Path -Path $path)){
	Write-Output "Creating directory: $path"
	New-Item -Path $path -ItemType Directory | Out-Null 
} else { 
	Write-Output "Deleting previously installed module"
	Remove-Item -Path "$path\*" -Force -Recurse 
}

Write-Output "Downloading archive from github"
$wc = New-Object System.Net.WebClient
$wc.DownloadFile($url, $zipfile)

# Unblock
 if ([Win32.PInvoke]::Win32FileExists($zipfile + ':Zone.Identifier')) {
	if ($PSCmdlet.ShouldProcess($_)) {
		$result_code = [Win32.PInvoke]::Win32DeleteFile($zipfile + ':Zone.Identifier')
		if ([Win32.PInvoke]::Win32FileExists($zipfile + ':Zone.Identifier')) {
			Write-Error ("Failed to unblock '{0}' the Win32 return code is '{1}'." -f $zipfile, $result_code)
		}
	}
}

Write-Output "Unzipping"
# Keep it backwards compatible
$shell = New-Object -COM Shell.Application
$zipPackage = $shell.NameSpace($zipfile)
$destinationFolder = $shell.NameSpace($temp)
$destinationFolder.CopyHere($zipPackage.Items())

Write-Output "Cleaning up"
Move-Item -Path "$temp\dbatools-master\*" $path
Remove-Item -Path "$temp\dbatools-master"
Remove-Item -Path $zipfile

Write-Output "Done! Please report any bugs to clemaire@gmail.com."
if ((Get-Command -Module dbatools).count -eq 0) { Import-Module "$path\dbatools.psd1" }
Get-Command -Module dbatools
Write-Output "`n`nIf you experience any function missing errors after update, please restart PowerShell or reload your profile."