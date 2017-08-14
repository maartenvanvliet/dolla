defmodule DollaTest do
  use ExUnit.Case
  alias Dolla.Receipt
  alias Dolla.Response
  doctest Dolla

  setup do
    bypass = Bypass.open
    Application.put_env(:dolla, :endpoint, "http://localhost:#{bypass.port}/verifyReceipt")
    {:ok, bypass: bypass}
  end

  test "verify a good receipt", %{bypass: bypass} do
    Bypass.expect bypass, fn conn ->
      assert "POST" == conn.method
      Plug.Conn.resp(conn, 200, DollaTest.Fixtures.receipt_with_iaps)
    end
    assert {:ok, %Response{receipt: %Receipt{}}} = Dolla.verify("RECEIPT_DATA")
  end

  test "fail an invalid receipt", %{bypass: bypass} do
    Bypass.expect bypass, fn conn ->
      Plug.Conn.resp(conn, 200, ~s({"status":21002}))
    end

    assert {:error, %Response{error: %Response.ValidationError{message: "The data in the receipt-data property was malformed or missing."}}} = Dolla.verify("BAD_DATA")
  end

  test "fail when the receipt cannot be validated", %{bypass: bypass} do
    Bypass.expect bypass, fn conn ->
      Plug.Conn.resp(conn, 200, ~s({"status":21003}))
    end

    assert {:error, %Response{error: %Response.ValidationError{message: "The receipt could not be authenticated."}}} = Dolla.verify("BAD_DATA")
  end

  test "fail when the receipt server is not available", %{bypass: bypass} do
    Bypass.expect bypass, fn conn ->
      Plug.Conn.resp(conn, 200, ~s({"status": 21005}))
    end
    assert {:error, %Response{error: %Response.ValidationError{message: "The receipt server is not currently available."}}} = Dolla.verify("Not available")
  end

  test "fail when a password is required", %{bypass: bypass} do
    Bypass.expect bypass, fn conn ->
      Plug.Conn.resp(conn, 200, ~s({"status":21004, "environment":"Production"}))
    end
    assert {:error, %Response{error: %Response.ValidationError{message: "The shared secret you provided does not match the shared secret on file for your account."}}} = Dolla.verify("No password")
  end

  test "fails when server is unreachable", %{bypass: bypass} do
    Bypass.down(bypass)
    assert {:error, %Response{error: %HTTPoison.Error{}}} = Dolla.verify("Unreachable")
  end

  test "when there is a server error", %{bypass: bypass} do
    Bypass.expect bypass, fn conn ->
      Plug.Conn.resp(conn, 503, "Destination host unreachable")
    end
    assert {:error, %Response{error: %Dolla.Client.ServerError{status_code: 503}}} = Dolla.verify("LOL BROKEN")
  end

  test "when the server returns garbage", %{bypass: bypass} do
    Bypass.expect bypass, fn conn ->
      Plug.Conn.resp(conn, 200, "YOU SHALL NOT PARSE!")
    end
    assert {:error, %Response{error: %Dolla.Response.ParseError{}}} = Dolla.verify("Lulz")
  end

  test "parses dates into Timex formats", %{bypass: bypass} do
    Bypass.expect bypass, fn conn ->
      assert "POST" == conn.method
      Plug.Conn.resp(conn, 200, DollaTest.Fixtures.receipt_with_iaps)
    end
    {:ok, %Response{receipt: %Receipt{in_app: [iap | _]}}} = Dolla.verify("RECEIPT_DATA")
    assert %DateTime{} = iap.purchase_date
    assert iap.product_id == "com.zova.recurring.1month"
  end

  test "switches to the sandbox with error 21007", %{bypass: prod} do
    sandbox = Bypass.open
    Application.put_env(:dolla, :sandbox, "http://localhost:#{sandbox.port}/verifyReceipt")

    Bypass.expect prod, fn conn ->
      assert "POST" == conn.method
      Plug.Conn.resp(conn, 200, ~s({"status":21007, "environment":"Production"}))
    end

    Bypass.expect sandbox, fn conn ->
      assert "POST" == conn.method
      Plug.Conn.resp(conn, 200, DollaTest.Fixtures.receipt_with_iaps)
    end
    {:ok, %Response{receipt: %Receipt{}}} = Dolla.verify("RECEIPT_DATA")
  end

end
