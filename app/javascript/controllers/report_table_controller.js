import { Controller } from "@hotwired/stimulus"

// Client-side column sort for Reports::TableComponent (docs/dev/reports/spec.md
// §2.5: "tri côté client"). No server round-trip: the whole table is already
// on the page, so sorting just reorders <tbody> rows in place.
export default class extends Controller {
  sort(event) {
    const index = parseInt(event.currentTarget.dataset.reportTableIndexParam, 10)
    const tbody = this.element.querySelector("tbody")
    const rows = Array.from(tbody.querySelectorAll("tr"))
    const ascending = this.element.dataset.sortIndex !== String(index) || this.element.dataset.sortDir !== "asc"

    rows.sort((a, b) => {
      const [va, vb] = [a, b].map((row) => this.#cellValue(row, index))
      const cmp = typeof va === "number" && typeof vb === "number" ? va - vb : String(va).localeCompare(String(vb))
      return ascending ? cmp : -cmp
    })

    rows.forEach((row) => tbody.appendChild(row))
    this.element.dataset.sortIndex = String(index)
    this.element.dataset.sortDir = ascending ? "asc" : "desc"
  }

  #cellValue(row, index) {
    const text = row.cells[index].textContent.trim()
    const numeric = Number(text.replace(/[^\d,.-]/g, "").replace(",", "."))
    return text !== "" && !Number.isNaN(numeric) ? numeric : text
  }
}
