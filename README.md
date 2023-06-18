lineblog-grab
=============

More information about the archiving project can be found on the ArchiveTeam wiki: [LINE BLOG](https://wiki.archiveteam.org/index.php/LINE_BLOG)

It is advised to use watchtower to automatically update the project. This requires watchtower:

    docker run --name watchtower --restart=unless-stopped -v /var/run/docker.sock:/var/run/docker.sock containrrr/watchtower --label-enable --cleanup --interval 3600

after which the project can be run:

    docker run --name archiveteam --label=com.centurylinklabs.watchtower.enable=true --restart=unless-stopped atdr.meo.ws/archiveteam/lineblog-grab --concurrent 1 YOURNICKHERE

Be sure to replace `YOURNICKHERE` with the nickname that you want to be shown as on the tracker. You don't need to register it, just pick a nickname you like.

