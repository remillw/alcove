module PaymentsHelper
  # "€4.99" in English, "4,99 €" in French: the format lives in the locale files
  def product_price(product)
    t("payments.price", amount: format("%.2f", product.price).tr(".", t("payments.decimal_separator")))
  end

  # numeric on purpose: month names would need a full set of date translations per locale
  def payments_date(time) = time.strftime(t("payments.date_format"))
end
