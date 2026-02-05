#
# This file is licensed under the Affero General Public License (AGPL) version 3.
#
# Copyright (C) 2024 CLAP
#
# Auto DM Bot Module
# Automatically creates a DM room between the bot and newly registered users.
#

import logging
from typing import Any, Optional

from synapse.api.constants import AccountDataTypes
from synapse.module_api import ModuleApi, run_as_background_process

logger = logging.getLogger(__name__)


class AutoDmBotConfig:
    def __init__(self, config: dict):
        self.enabled: bool = config.get("enabled", True)
        self.bot_user_id: Optional[str] = config.get("bot_user_id")
        self.welcome_message: Optional[str] = config.get("welcome_message")
        self.room_name: Optional[str] = config.get("room_name")

        if self.enabled and not self.bot_user_id:
            raise ValueError(
                "bot_user_id is required when auto_dm_bot module is enabled"
            )


class AutoDmBot:
    def __init__(self, config: AutoDmBotConfig, api: ModuleApi):
        self._api = api
        self._config = config
        self.server_name = api.server_name

        if not self._config.enabled:
            logger.info("AutoDmBot module is disabled")
            return

        if not self._config.bot_user_id:
            logger.warning("AutoDmBot: bot_user_id not configured, module disabled")
            return

        logger.info(
            "AutoDmBot module initialized with bot_user_id=%s",
            self._config.bot_user_id,
        )

        self._api.register_account_validity_callbacks(
            on_user_registration=self.on_user_registration,
        )

    async def on_user_registration(self, user_id: str) -> None:
        if not self._config.enabled or not self._config.bot_user_id:
            return

        if user_id == self._config.bot_user_id:
            logger.debug("Skipping DM creation for bot user itself")
            return

        if not self._api.is_mine(user_id):
            logger.debug("Skipping DM creation for non-local user %s", user_id)
            return

        logger.info("New user registered: %s, creating DM with bot", user_id)

        run_as_background_process(
            "auto_dm_bot_create_dm",
            self._create_dm_with_bot,
            user_id,
        )

    async def _create_dm_with_bot(self, user_id: str) -> None:
        bot_user_id = self._config.bot_user_id
        if not bot_user_id:
            return

        try:
            room_config: dict[str, Any] = {
                "is_direct": True,
                "invite": [user_id],
                "preset": "trusted_private_chat",
                "creation_content": {
                    "m.federate": False,
                },
            }

            if self._config.room_name:
                room_config["name"] = self._config.room_name

            room_id, _ = await self._api.create_room(
                user_id=bot_user_id,
                config=room_config,
                ratelimit=False,
            )

            logger.info(
                "Created DM room %s between bot %s and user %s",
                room_id,
                bot_user_id,
                user_id,
            )

            await self._mark_room_as_direct_message(bot_user_id, user_id, room_id)
            await self._mark_room_as_direct_message(user_id, bot_user_id, room_id)

            if self._config.welcome_message:
                await self._send_welcome_message(room_id, bot_user_id)

        except Exception as e:
            logger.error(
                "Failed to create DM room for user %s: %s",
                user_id,
                e,
                exc_info=True,
            )

    async def _mark_room_as_direct_message(
        self, user_id: str, dm_user_id: str, room_id: str
    ) -> None:
        try:
            dm_map: dict[str, tuple[str, ...]] = dict(
                await self._api.account_data_manager.get_global(
                    user_id, AccountDataTypes.DIRECT
                )
                or {}
            )

            if dm_user_id not in dm_map:
                dm_map[dm_user_id] = (room_id,)
            else:
                dm_rooms_for_user = dm_map[dm_user_id]
                if room_id not in dm_rooms_for_user:
                    dm_map[dm_user_id] = tuple(dm_rooms_for_user) + (room_id,)

            await self._api.account_data_manager.put_global(
                user_id, AccountDataTypes.DIRECT, dm_map
            )

            logger.debug(
                "Marked room %s as DM for user %s with %s",
                room_id,
                user_id,
                dm_user_id,
            )
        except Exception as e:
            logger.warning(
                "Failed to mark room %s as DM for user %s: %s",
                room_id,
                user_id,
                e,
            )

    async def _send_welcome_message(self, room_id: str, bot_user_id: str) -> None:
        try:
            event_dict = {
                "type": "m.room.message",
                "room_id": room_id,
                "sender": bot_user_id,
                "content": {
                    "msgtype": "m.text",
                    "body": self._config.welcome_message,
                },
            }

            await self._api.create_and_send_event_into_room(event_dict)
            logger.debug("Sent welcome message to room %s", room_id)
        except Exception as e:
            logger.warning(
                "Failed to send welcome message to room %s: %s",
                room_id,
                e,
            )


def parse_config(config: dict) -> AutoDmBotConfig:
    return AutoDmBotConfig(config)
