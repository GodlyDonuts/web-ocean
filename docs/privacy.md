# Ocean privacy

Ocean has no account system, analytics, advertising or automatic support uploads. Rendering happens on your Mac. First-run environment lookup/setup begins after **Use Ocean**; opening the welcome screen does not need a GPS permission prompt.

## Location and weather

Ocean uses [IPWhois](https://ipwhois.io/privacy) to estimate the general area of your internet connection. The provider sees your public IP as part of the request. Ocean stores rounded coordinates and time zone locally, rather than your raw IP address. It normally refreshes this estimate once per day, with failure backoff and an offline cache. A VPN can change the apparent area.

Ocean sends the approximate coordinates to [Open-Meteo](https://open-meteo.com/en/terms) for weather, normally at most every 15 minutes. The weather service also receives normal connection metadata, including your IP address. Weather data is credited to Open-Meteo under CC BY 4.0. The current endpoint is for non-commercial use; commercial distribution needs appropriate service arrangements.

These services have their own policies and availability limits. Ocean’s claim that it does not store your raw IP does not mean providers cannot receive or log it.

## On your Mac

Preferences, approximate location/time-zone data, weather and cached astronomy timings stay in your user Library. A small local cache lets the wallpaper extension and screen saver use the same environment. No password, GPS, microphone, camera, screen-recording or accessibility permission is requested by Ocean’s own runtime. macOS may require approval for login-item registration or an unsigned beta download.

Choosing Turn Off Ocean restores the previous appearance and stops the controller. It retains preferences and cached environment data. Removing the app does not automatically remove these saved settings.

## Help and updates

GitHub buttons open the official release/issue pages in your browser. GitHub then receives the normal information associated with a website visit. Ocean does not upload logs or install updates in the background. Copy Support Info uses your clipboard only after you click it; it omits IP addresses and saved coordinates. Review any screenshot or issue text before posting it yourself.

Provider policies and terms were checked while preparing the November 2026 beta. Recheck them before a larger or commercial distribution.
