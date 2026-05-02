Rails.application.routes.draw do
  resource  :session
  resource  :registration, only: [ :new, :create ], as: :registration
  resources :passwords, param: :token

  get  "signup",  to: "registrations#new"
  get  "login",   to: "sessions#new"
  post "logout",  to: "sessions#destroy"

  get "dashboard", to: "dashboards#show", as: :dashboard

  namespace :admin do
    root to: "dashboard#index"
    resources :email_tests, only: :create
  end

  # Tool 06 — Invoice maker
  get "invoice",             to: "invoices#new",    as: :new_invoice
  resources :invoices, only: [ :create, :update, :destroy ], param: :slug
  get  "invoices/:slug/edit", to: "invoices#edit",   as: :edit_invoice

  # Tool 07 — Sign PDF
  get  "sign",                to: "signatures#new",  as: :sign
  resources :digital_signatures, only: [ :create, :destroy ]

  # Tools 08 / 09 — Media (client-side ffmpeg.wasm)
  get  "media",               to: redirect("/media/mp4-to-mp3"), as: :media_root
  get  "media/:op",           to: "pages#media",
                              as: :media,
                              constraints: { op: /mp4-to-mp3|webm-to-mp4|compress-video/ }
  get  "media-debug",         to: "pages#media_debug"

  root "pages#home"

  # Static pages
  get "about",     to: "pages#about",     as: :about
  get "roadmap",   to: "pages#roadmap",   as: :roadmap
  get "contact",   to: "pages#contact",   as: :contact
  get "privacy",   to: "pages#privacy",   as: :privacy
  get "changelog", to: "pages#changelog", as: :changelog
  get "robots.txt",  to: "seo#robots",  defaults: { format: :text }
  get "sitemap.xml", to: "seo#sitemap", defaults: { format: :xml }
  resources :feedback_submissions, only: :create

  # Tool 01 — HEIC → JPG (client-side)
  get "heic-to-jpg", to: "pages#heic", as: :heic

  # Tool 02 — PDF (client-side, multiple ops)
  get "merge-pdf",   to: "pages#pdf", defaults: { op: "merge" }
  get "split-pdf",   to: "pages#pdf", defaults: { op: "split" }
  get "rotate-pdf",  to: "pages#pdf", defaults: { op: "rotate" }
  get "compress-pdf", to: "pages#pdf", defaults: { op: "compress" }
  get "pdf-to-docx", to: "pages#pdf", defaults: { op: "pdf-to-docx" }
  get "docx-to-pdf", to: "pages#pdf", defaults: { op: "docx-to-pdf" }
  get "word-to-csv", to: "pages#pdf", defaults: { op: "word-to-csv" }
  get "pdf-to-jpg",  to: "pages#pdf", defaults: { op: "pdf-to-jpg" }
  get "pdf-to-png",  to: "pages#pdf", defaults: { op: "pdf-to-png" }
  get "pdf",        to: redirect("/pdf/merge"), as: :pdf_root
  get "pdf/:op",    to: "pages#pdf",
                    as: :pdf,
                    constraints: { op: /merge|split|rotate|compress|pdf-to-docx|docx-to-pdf|word-to-csv|pdf-to-jpg|pdf-to-png/ }
  post "document-conversions/:op", to: "document_conversions#create",
                                   as: :document_conversion,
                                   constraints: { op: /pdf-to-docx|docx-to-pdf|word-to-csv|pdf-to-jpg|pdf-to-png/ }

  # Tool 05 — Image tools (client-side)
  get "images",        to: redirect("/images/compress"), as: :images_root
  get "images/:op",    to: "pages#image",
                       as: :image,
                       constraints: { op: /compress/ }

  # Tool 03 — Is It Down? (server-side, boards)
  get  "down",              to: "down#index",   as: :down
  post "down/check",        to: "down#check",   as: :down_check
  resources :boards, only: [ :create, :show ], path: "down/b", param: :slug do
    member do
      post :recheck
    end
  end

  # Tool 04 — Bulk URL opener (server-side sets)
  get "open",              to: "url_sets#new",    as: :open_urls
  resources :url_sets, only: [ :create ], path: "o"
  get "o/:slug",           to: "url_sets#show",   as: :url_set

  # Health / PWA
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "up" => "rails/health#show", as: :rails_health_check
end
