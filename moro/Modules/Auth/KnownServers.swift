//
//  KnownServers.swift
//  moro
//
//  A bundled snapshot of well-known Mastodon servers. It only decorates the login
//  starfield (each server is one stable star); logging in never depends on it, and
//  any domain not listed still works.
//

enum KnownServers {
    static let domains: [String] = {
        var seen = Set<String>()
        return (RecommendedServers.all + listed).filter { seen.insert($0).inserted }
    }()

    private static let listed = [
        "mastodon.social", "mastodon.online", "mstdn.social", "mas.to", "mastodon.world", "techhub.social",
        "universeodon.com", "fosstodon.org", "hachyderm.io", "infosec.exchange", "ioc.exchange", "toot.community",
        "mastodon.cloud", "mastodon.art", "mastodon.green", "mastodon.sdf.org", "mastodon.lol", "mastodon.xyz",
        "mastodon.ie", "mastodon.scot", "mastodon.nz", "mastodon.au", "aus.social", "mstdn.ca", "mastodonapp.uk",
        "mastodon.nl", "mastodon.uno", "mastodon.bida.im", "mastodon.es", "mastodon.com.br", "masto.donte.com.br",
        "mastodon.top", "masto.ai", "social.vivaldi.net", "social.coop", "social.linux.pizza", "social.tchncs.de",
        "chaos.social", "troet.cafe", "norden.social", "det.social", "nrw.social", "muenchen.social",
        "berlin.social", "metalhead.club", "todon.eu", "todon.nl", "piaille.fr", "framapiaf.org", "mamot.fr",
        "kolektiva.social", "sfba.social", "bne.social", "mathstodon.xyz", "scholar.social", "sciencemastodon.com",
        "journa.host", "newsie.social", "mastodon.gamedev.place", "ruby.social", "phpc.social", "toot.cafe",
        "tech.lgbt", "wandering.shop", "octodon.social", "qoto.org", "mstdn.jp", "pawoo.net", "fedibird.com",
        "mastodon-japan.net", "best-friends.chat", "m.cmx.im", "o3o.ca", "mstdn.party", "mstdn.science",
        "mstdn.games", "mstdn.plus", "mastodon.cat", "mastodon.sk", "mastodon.fi", "mastodon.se", "mastodon.no",
        "mastodon.pl", "mastodon.lt", "mastodon.hr", "mastodon.ml", "mastodon.tedomum.net", "pouet.chapril.org",
        "eldritch.cafe", "witches.live", "toot.wales", "social.politicaconciencia.org", "mastodon.partipirate.org",
        "botsin.space", "vis.social", "photog.social", "pixelfed.social", "indieweb.social", "writing.exchange",
        "historians.social", "lingo.lol", "urbanists.social", "climatejustice.social", "union.place",
        "disabled.social", "blind.social", "dads.cool", "mastodon.education", "mastodon.radio", "podcastindex.social",
        "musician.social", "linernotes.club", "mstdn.business", "fediscience.org", "fosstodon.social",
        "functional.cafe", "types.pl", "hci.social", "akademienl.social", "mastodon.acm.org", "genomic.social",
        "astrodon.social", "spacey.space", "birds.town", "mastodon.cc", "masto.nu", "social.lol", "c.im",
        "home.social", "mastodon.me.uk", "mstdn.games", "mastodon.london", "mastodon.nu", "toot.io",
        "social.treehouse.systems", "tenforward.social", "sigmoid.social", "mastodon.design", "front-end.social",
        "dotnet.social", "floss.social", "emacs.ch", "hostux.social", "framapiaf.org", "zirk.us", "mastodon.bayern",
        "graz.social", "fedi.at", "swiss.social", "mastodon.free-solutions.org", "mastodon.tn", "mastodon.africa",
        "mastodon.in.th", "mastodon.id", "mastodon.kr", "qdon.space", "planet.moe", "mastodon.tw", "g0v.social",
        "mastodon.hk", "mastodon.sg", "mastodon.my",
    ]
}
