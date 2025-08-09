Required parameters for this command:
--PARMZ--

AND HaveParameter tests must be structured EXACTLY like this:

```powershell
$params = @(
    "parameter1",
    "parameter2",
    "etc"
)
It "has the required parameter: <_>" -ForEach $params {
    $currentTest | Should -HaveParameter $PSItem
}
```

NO OTHER CHANGES SHOULD BE MADE TO THE TEST FILE