package commands

import "hpk/pkg/version"

var (
	BuildVersion = version.Version
	BuildTime    = version.BuildTime
	K8sVersion   = version.K8sVersion
)
