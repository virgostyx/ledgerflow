import { application } from "controllers/application"

import JournalEntryFormController from "controllers/journal_entry_form_controller"
application.register("journal-entry-form", JournalEntryFormController)

import AccountSearchController from "controllers/account_search_controller"
application.register("account-search", AccountSearchController)
