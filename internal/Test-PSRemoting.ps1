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
    [System.Management.Automation.Credential()]$Credential = [System.Management.Automation.PSCredential]::Empty
  )
 
  begin {
    Write-Verbose -Message "Starting $($MyInvocation.Mycommand)"  
  } #begin
 
  process {
    Write-Verbose -Message "Testing $computername"
    Try {
      $r = Test-WSMan -ComputerName $Computername -Credential $Credential -Authentication Default -ErrorAction Stop
      $True 
    }
    Catch {
      Write-Verbose $_.Exception.Message
      $False
 
    }
 
  } #process
 
  end {
    Write-Verbose -Message "Ending $($MyInvocation.Mycommand)"
  } #end
 
} #close function
