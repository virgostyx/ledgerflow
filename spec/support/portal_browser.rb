# The browser of the system suite is one for all the examples: what a portal example left in it (documents waiting in IndexedDB, copies of pages, the service worker) must not reach the next one,
# and no page may still be running a request when the database is cleaned (the server would meet a session whose person is gone).
RSpec.configure do |config|
  config.after(:each, :portal_browser) do
    begin
      page.execute_script(<<~JS)
        indexedDB.deleteDatabase('lf-portal');
        caches.keys().then((keys) => keys.forEach((key) => caches.delete(key)));
        navigator.serviceWorker.getRegistrations().then((all) => all.forEach((r) => r.unregister()));
      JS
      sleep 0.3
      page.driver.browser.network_conditions = { offline: false, latency: 0, download_throughput: -1, upload_throughput: -1 }
      visit 'about:blank'
    rescue StandardError
      nil # no page was open
    end
  end
end
