function Get-SmoServerForDynamicParams {
    ##############################
    # THIS DOES NOT SEEM TO BE USED
    ##############################
    if ($fakeBoundParameter.length -eq 0) { return }

    $SqlInstance = $fakeBoundParameter['SqlInstance']
    $sqlcredential = $fakeBoundParameter['SqlCredential']

    if ($null -eq $SqlInstance) {
        $SqlInstance = $fakeBoundParameter['sqlinstance']
    }
    if ($null -eq $SqlInstance) {
        $SqlInstance = $fakeBoundParameter['source']
    }
    if ($null -eq $sqlcredential) {
        $sqlcredential = $fakeBoundParameter['Credential']
    }

    if ($SqlInstance) {
        Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential -ParameterConnection
    }
}