if (-not ("Dataplat.Dbatools.Message.LegacyMessageTransforms" -as [type])) {
    throw "Explicit legacy message transforms require the LegacyMessageTransforms registration API from dbatools.library."
}
[Dataplat.Dbatools.Message.LegacyMessageTransforms]::Register()
