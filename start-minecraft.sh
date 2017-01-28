#!/bin/bash

#umask 002
export HOME=/data
echo "eula=true" >> eula.txt

VERSIONS_JSON=https://launchermeta.mojang.com/mc/game/version_manifest.json

echo "Checking version information."
case "X$VERSION" in
  X|XLATEST|Xlatest)
    VANILLA_VERSION=`curl -sSL $VERSIONS_JSON | jq -r '.latest.release'`
  ;;
  XSNAPSHOT|Xsnapshot)
    VANILLA_VERSION=`curl -sSL $VERSIONS_JSON | jq -r '.latest.snapshot'`
  ;;
  X[1-9]*)
    VANILLA_VERSION=$VERSION
  ;;
  *)
    VANILLA_VERSION=`curl -sSL $VERSIONS_JSON | jq -r '.latest.release'`
  ;;
esac

cd /data

function buildSpigotFromSource {
  echo "Building Spigot $VANILLA_VERSION from source, might take a while, get some coffee"
  mkdir /data/temp
  cd /data/temp
  wget -q -P /data/temp https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar && \
    java -jar /data/temp/BuildTools.jar --rev $VANILLA_VERSION 2>&1 |tee /data/spigot_build.log| while read l; do echo -n .; done; echo "done"
  mv spigot-*.jar /data/spigot_server.jar
  mv craftbukkit-*.jar /data/craftbukkit_server.jar
  echo "Cleaning up"
  rm -rf /data/temp
  cd /data
}

function downloadSpigot {
  local match
  case "$TYPE" in
    *BUKKIT|*bukkit)
      match="Craftbukkit"

      ;;
    *)
      match="Spigot"
      ;;
  esac

  downloadUrl=$(restify --class=jar-div https://mcadmin.net/ | \
    jq --arg version "$match $VANILLA_VERSION" -r -f /usr/share/mcadmin.jq)
  if [[ -n $downloadUrl ]]; then
    echo "Downloading $match"
    wget -q -O $SERVER "$downloadUrl"
    status=$?
    if [ $status != 0 ]; then
      echo "ERROR: failed to download from $downloadUrl due to (error code was $status)"
      exit 3
    fi
  else
    echo "ERROR: Version $VANILLA_VERSION is not supported for $TYPE"
    echo "       Refer to https://mcadmin.net/ for supported versions"
    exit 2
  fi
}

function installVanilla {
  SERVER="minecraft_server.$VANILLA_VERSION.jar"

  if [ ! -e $SERVER ]; then
    echo "Downloading $SERVER ..."
    wget -q https://s3.amazonaws.com/Minecraft.Download/versions/$VANILLA_VERSION/$SERVER
  fi
}

echo "Checking type information."
case "$TYPE" in
  *BUKKIT|*bukkit|SPIGOT|spigot)
    case "$TYPE" in
      *BUKKIT|*bukkit)
        SERVER=craftbukkit_server.jar
        ;;
      *)
        SERVER=spigot_server.jar
        ;;
    esac

    if [ ! -f $SERVER ]; then
       if [[ "$BUILD_SPIGOT_FROM_SOURCE" = TRUE || "$BUILD_SPIGOT_FROM_SOURCE" = true || "$BUILD_FROM_SOURCE" = TRUE || "$BUILD_FROM_SOURCE" = true ]]; then
         buildSpigotFromSource
       else
         downloadSpigot
       fi
    fi
    # normalize on Spigot for operations below
    TYPE=SPIGOT
  ;;

  PAPER|paper)
    SERVER=paper_server.jar
    if [ ! -f $SERVER ]; then
      downloadPaper
    fi
    # normalize on Spigot for operations below
    TYPE=SPIGOT
  ;;

  FORGE|forge)
    TYPE=FORGE
    installForge
  ;;

  VANILLA|vanilla)
    installVanilla
  ;;

  *)
      echo "Invalid type: '$TYPE'"
      echo "Must be: VANILLA, FORGE, SPIGOT"
      exit 1
  ;;

esac

function setServerProp {
  local prop=$1
  local var=$2
  if [ -n "$var" ]; then
    echo "Setting $prop to $var"
    sed -i "/$prop\s*=/ c $prop=$var" /data/server.properties
  fi

}

if [ ! -e server.properties ]; then
  echo "Creating server.properties"
  cp /tmp/server.properties .

  if [ -n "$WHITELIST" ]; then
    echo "Creating whitelist"
    sed -i "/whitelist\s*=/ c whitelist=true" /data/server.properties
    sed -i "/white-list\s*=/ c white-list=true" /data/server.properties
  fi

  setServerProp "motd" "$MOTD"
  setServerProp "allow-nether" "$ALLOW_NETHER"
  setServerProp "announce-player-achievements" "$ANNOUNCE_PLAYER_ACHIEVEMENTS"
  setServerProp "enable-command-block" "$ENABLE_COMMAND_BLOCK"
  setServerProp "spawn-animals" "$SPAWN_ANIMAILS"
  setServerProp "spawn-monsters" "$SPAWN_MONSTERS"
  setServerProp "spawn-npcs" "$SPAWN_NPCS"
  setServerProp "generate-structures" "$GENERATE_STRUCTURES"
  setServerProp "spawn-npcs" "$SPAWN_NPCS"
  setServerProp "view-distance" "$VIEW_DISTANCE"
  setServerProp "hardcore" "$HARDCORE"
  setServerProp "max-build-height" "$MAX_BUILD_HEIGHT"
  setServerProp "force-gamemode" "$FORCE_GAMEMODE"
  setServerProp "hardmax-tick-timecore" "$MAX_TICK_TIME"
  setServerProp "enable-query" "$ENABLE_QUERY"
  setServerProp "query.port" "$QUERY_PORT"
  setServerProp "enable-rcon" "$ENABLE_RCON"
  setServerProp "rcon.password" "$RCON_PASSWORD"
  setServerProp "rcon.port" "$RCON_PORT"
  setServerProp "max-players" "$MAX_PLAYERS"
  setServerProp "max-world-size" "$MAX_WORLD_SIZE"
  setServerProp "level-name" "$LEVEL"
  setServerProp "level-seed" "$SEED"
  setServerProp "pvp" "$PVP"
  setServerProp "generator-settings" "$GENERATOR_SETTINGS"
  setServerProp "online-mode" "$ONLINE_MODE"

  if [ -n "$LEVEL_TYPE" ]; then
    # normalize to uppercase
    LEVEL_TYPE=${LEVEL_TYPE^^}
    echo "Setting level type to $LEVEL_TYPE"
    # check for valid values and only then set
    case $LEVEL_TYPE in
      DEFAULT|FLAT|LARGEBIOMES|AMPLIFIED|CUSTOMIZED)
        sed -i "/level-type\s*=/ c level-type=$LEVEL_TYPE" /data/server.properties
        ;;
      *)
        echo "Invalid LEVEL_TYPE: $LEVEL_TYPE"
	exit 1
	;;
    esac
  fi

  if [ -n "$DIFFICULTY" ]; then
    case $DIFFICULTY in
      peaceful|0)
        DIFFICULTY=0
        ;;
      easy|1)
        DIFFICULTY=1
        ;;
      normal|2)
        DIFFICULTY=2
        ;;
      hard|3)
        DIFFICULTY=3
        ;;
      *)
        echo "DIFFICULTY must be peaceful, easy, normal, or hard."
        exit 1
        ;;
    esac
    echo "Setting difficulty to $DIFFICULTY"
    sed -i "/difficulty\s*=/ c difficulty=$DIFFICULTY" /data/server.properties
  fi

  if [ -n "$MODE" ]; then
    echo "Setting mode"
    case ${MODE,,?} in
      0|1|2|3)
        ;;
      su*)
        MODE=0
        ;;
      c*)
        MODE=1
        ;;
      a*)
        MODE=2
        ;;
      sp*)
        MODE=3
        ;;
      *)
        echo "ERROR: Invalid game mode: $MODE"
        exit 1
        ;;
    esac

    sed -i "/^gamemode\s*=/ c gamemode=$MODE" /data/server.properties
  fi
fi


if [ -n "$OPS" -a ! -e ops.txt.converted ]; then
  echo "Setting ops"
  echo $OPS | awk -v RS=, '{print}' >> ops.txt
fi

if [ -n "$WHITELIST" -a ! -e white-list.txt.converted ]; then
  echo "Setting whitelist"
  echo $WHITELIST | awk -v RS=, '{print}' >> white-list.txt
fi

if [ -n "$ICON" -a ! -e server-icon.png ]; then
  echo "Using server icon from $ICON..."
  # Not sure what it is yet...call it "img"
  wget -q -O /tmp/icon.img $ICON
  specs=$(identify /tmp/icon.img | awk '{print $2,$3}')
  if [ "$specs" = "PNG 64x64" ]; then
    mv /tmp/icon.img /data/server-icon.png
  else
    echo "Converting image to 64x64 PNG..."
    convert /tmp/icon.img -resize 64x64! /data/server-icon.png
  fi
fi

# Make sure files exist to avoid errors
if [ ! -e banned-players.json ]; then
	echo '' > banned-players.json
fi
if [ ! -e banned-ips.json ]; then
	echo '' > banned-ips.json
fi

if [ "$TYPE" = "SPIGOT" ]; then
  if [ -d /plugins ]; then
    echo Copying any Bukkit plugins over
    cp -r /plugins /data
  fi
fi

exec java $JVM_OPTS -jar $SERVER "$@" $EXTRA_ARGS 
