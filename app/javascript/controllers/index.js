import { application } from "controllers/application"

import JournalEntryFormController from "controllers/journal_entry_form_controller"
application.register("journal-entry-form", JournalEntryFormController)

import AccountSearchController from "controllers/account_search_controller"
application.register("account-search", AccountSearchController)

import FlashController from "controllers/flash_controller"
application.register("flash", FlashController)

import ModalController from "controllers/modal_controller"
application.register("modal", ModalController)

import ConfirmController from "controllers/confirm_controller"
application.register("confirm", ConfirmController)

import FilterPanelController from "controllers/filter_panel_controller"
application.register("filter-panel", FilterPanelController)

import BackToTopController from "controllers/back_to_top_controller"
application.register("back-to-top", BackToTopController)

import LoadingOverlayController from "controllers/loading_overlay_controller"
application.register("loading-overlay", LoadingOverlayController)

import CalculatorController from "controllers/calculator_controller"
application.register("calculator", CalculatorController)

import CurrencyConverterController from "controllers/currency_converter_controller"
application.register("currency-converter", CurrencyConverterController)

import MusicPlayerController from "controllers/music_player_controller"
application.register("music-player", MusicPlayerController)

import DropdownController from "controllers/dropdown_controller"
application.register("dropdown", DropdownController)

import TooltipController from "controllers/tooltip_controller"
application.register("tooltip", TooltipController)

import ModalTriggerController from "controllers/modal_trigger_controller"
application.register("modal-trigger", ModalTriggerController)

import FloatingLabelController from "controllers/floating_label_controller"
application.register("floating-label", FloatingLabelController)

import CookieBannerController from "controllers/cookie_banner_controller"
application.register("cookie-banner", CookieBannerController)

import InvoiceFormController from "controllers/invoice_form_controller"
application.register("invoice-form", InvoiceFormController)
