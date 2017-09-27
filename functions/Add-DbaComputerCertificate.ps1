function Add-DbaComputerCertificate {
  <#
    .SYNOPSIS
      Adds a computer certificate - useful for older systems.

    .DESCRIPTION
      Adds a computer certificate from a local or remote computer.

    .PARAMETER ComputerName
      The target SQL Server. Defaults to localhost.

    .PARAMETER Credential
      Allows you to login to $ComputerName using alternative credentials.

    .PARAMETER Password
      The password for the certificate, if it is password protected.

    .PARAMETER Certificate
      The target certificate object.

    .PARAMETER Path
      The local path to the target certificate object.

    .PARAMETER Store
      Certificate store. Default is LocalMachine.

    .PARAMETER Folder
      Certificate folder. Default is My (Personal).
    
    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER Silent
      If this switch is enabled, the internal messaging functions will be silenced.
        
    .NOTES
      Tags: Certificate

      Website: https://dbatools.io
      Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
      License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .EXAMPLE
      Add-DbaComputerCertificate -ComputerName Server1 -Path C:\temp\cert.cer

      Adds the local C:\temp\cer.cer to the remote server Server1 in LocalMachine\My (Personal).

    .EXAMPLE
      Add-DbaComputerCertificate -Path C:\temp\cert.cer

      Adds the local C:\temp\cer.cer to the local computer's LocalMachine\My (Personal) certificate store.

#>
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
  param (
    [Alias("ServerInstance", "SqlServer", "SqlInstance")]
    [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
    [PSCredential]$Credential,
    [securestring]$Password,
    [parameter(ValueFromPipeline)]
    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
    [string]$Path,
    [string]$Store = "LocalMachine",
    [string]$Folder = "My",
    [switch]$Silent
  )
	
  begin {
		
    if ($Path) {
      if (!(Test-Path -Path $Path)) {
        Stop-Function -Message "Path ($Path) does not exist."
        return
      }

      try {
        # This may be too much, but ¯\_(ツ)_/¯
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $Certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
        $Certificate.Import($bytes, $Password, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
      }
      catch {
        Stop-Function -Message "Can't import certificate." -ErrorRecord $_ -Continue
      }
    }
  }
  process {
    if (Test-FunctionInterrupt) { return }
		
    if (!$Certificate -and !$Path) {
      Write-Message -Level Warning -Message "You must specify either Certificate or Path"
      return
    }
		
    if ($Certificate) {
      try {
        $certData = $Certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::PFX, $Password)
      }
      catch {
        Stop-Function -Message "Can't export certificate" -ErrorRecord $_ -Continue
      }
    }
		
    foreach ($computer in $ComputerName) {
			
      if (![dbavalidate]::IsLocalhost($computer) -and !$Password) {
        $Password = ((65 .. 90) + (97 .. 122) | Get-Random -Count 29 | ForEach-Object { [char]$_ }) -join "" | ConvertTo-SecureString -AsPlainText -Force
      }
			
      $scriptBlock = {
        $Store = $args[2]
        $Folder = $args[3]
				
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
        $cert.Import($args[0], $args[1], [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet)
        Write-Verbose "Importing cert to $Folder\$Store"
        $tempStore = New-Object System.Security.Cryptography.X509Certificates.X509Store($Folder, $Store)
        $tempStore.Open('ReadWrite')
        $tempStore.Add($cert)
        $tempStore.Close()
				
        Write-Verbose "Searching Cert:\$Store\$Folder"
        Get-ChildItem "Cert:\$Store\$Folder" -Recurse | Where-Object { $_.Thumbprint -eq $cert.Thumbprint }
      }
			
      if ($PScmdlet.ShouldProcess("local", "Connecting to $computer to import cert")) {
        try {
          Invoke-Command2 -ComputerName $computer -Credential $Credential -ArgumentList $certdata, $Password, $Store, $Folder -ScriptBlock $scriptblock -ErrorAction Stop |
            Select-DefaultView -Property FriendlyName, DnsNameList, Thumbprint, NotBefore, NotAfter, Subject, Issuer
        }
        catch {
          Stop-Function -Message "Failure" -ErrorRecord $_ -Target $computer -Continue
        }
      }
    }
  }
}
