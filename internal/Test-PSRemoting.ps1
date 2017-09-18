#requires -version 3.0
 
function Test-PSRemoting {
<#
Jeff Hicks
https://www.petri.com/test-network-connectivity-powershell-test-connection-cmdlet
#>
  [cmdletbinding()]
  param(
    [Parameter(Position=0,Mandatory,HelpMessage = "Enter a computername",ValueFromPipeline)]
    [ValidateNotNullorEmpty()]
    [string]$Computername,
    $Credential = [System.Management.Automation.PSCredential]::Empty,
	[switch]$Silent
  )
 
  begin {
  	Write-Message -Level Verbose -Message "Starting $($MyInvocation.Mycommand)"
  } #begin
 
  process {
    Write-Message -Level Verbose -Message "Testing $computername"
    try {
      $r = Test-WSMan -ComputerName $Computername -Credential $Credential -Authentication Default -ErrorAction Stop
      $True 
    }
    catch {
      Stop-Function -Message "Remote testing failed for computer $ComputerName" -Target $ComputerName -ErrorRecord $_ -Continue
      return $false
    }
    
  } #Process
 
  end {
    Write-Message -Level Verbose -Message "Ending $($MyInvocation.Mycommand)"
  } #end
 
} #close function
