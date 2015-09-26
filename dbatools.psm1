# Strictmode coming when I've got time.  Set-StrictMode -Version Latest

foreach ($function in (Get-ChildItem "$PSScriptRoot\Functions\*.ps1")) { . $function  }
