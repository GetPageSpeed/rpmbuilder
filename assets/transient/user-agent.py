import dnf


class RpmBuilderUa(dnf.Plugin):
    name = 'rpmbuilder_ua'

    def config(self):
        repos = self.base.repos.get_matching('*getpagespeed*')
        repos.set_http_headers(["User-Agent: XXXXXXXXXX"])
