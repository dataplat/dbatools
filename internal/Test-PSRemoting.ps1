#requires -version 3.0
 
Function Test-PSRemoting {
<#
Jeff Hicks
https://www.petri.com/test-network-connectivity-powershell-test-connection-cmdlet
#>
  [cmdletbinding()]
 
  Param(
    [Parameter(Position=0,Mandatory,HelpMessage = "Enter a computername",ValueFromPipeline)]
    [ValidateNotNullorEmpty()]
    [string]$Computername,
    $Credential = [System.Management.Automation.PSCredential]::Empty
  )
 
  Begin {
    Write-Message -Level Verbose -Message "Starting $($MyInvocation.Mycommand)"
  } #begin
 
  Process {
    Write-Message -Level Verbose -Message "Testing $computername"
    Try {
      $r = Test-WSMan -ComputerName $Computername -Credential $Credential -Authentication Default -ErrorAction Stop
      $True 
    }
    Catch {
      Stop-Function -Message "Remote testing failed for computer $ComputerName" -Target $ComputerName -ErrorRecord $_ -Continue
      return $false
    }
    
  } #Process
 
  End {
    Write-Message -Level Verbose -Message "Ending $($MyInvocation.Mycommand)"
  } #end
 
} #close function
