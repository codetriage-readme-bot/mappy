module Language.ExecutorSpec (spec) where

import Test.Hspec

import Language.Ast
import Language.Executor

import qualified Data.Map as M

simple_def name val = MappyDef (MappyNamedValue name) (MappyKeyword val)

spec :: Spec
spec = do
  describe "exec" $ do
    describe "given main simply binds to something else in the environment" $ do
      let
        code = [
          simple_def "foo" "bar",
          MappyDef (MappyNamedValue "main") (MappyNamedValue "foo")
          ]

      it "evaluates to whatever that name evaluates to when looked up" $ do
        exec code `shouldBe` Right (MappyKeyword "bar")

    describe "given main is simply a map" $ do
      let main = [MappyDef (MappyNamedValue "main") map]
          map = MappyMap $ M.singleton (MappyKeyword "a") (MappyKeyword "b")

      it "evaluates to just that map" $ do
        exec main `shouldBe` Right map

    describe "given main is simply a keyword" $ do
      let main = [MappyDef (MappyNamedValue "main") (MappyKeyword "foobar")]

      it "evaluates to just that keyword" $ do
        exec main `shouldBe` Right (MappyKeyword "foobar")

    describe "given a lot of repeats, including main" $ do
      let
        defs = [
          simple_def "foo" "bar",
          simple_def "foo" "bar",
          simple_def "spaz" "bar",
          simple_def "spaz" "bar",
          simple_def "main" "spaz",
          simple_def "main" "spaz"]

      it "errors with multiple repeated definition errors" $ do
        exec defs `shouldBe` Left [RepeatedDefinition "main", RepeatedDefinition "spaz", RepeatedDefinition "foo"]

    describe "given some definitions that are repeated, with a main" $ do
      let defs = [simple_def "foo" "bar", simple_def "foo" "bar", simple_def "main" "spaz"]

      it "errors with a repeated definition error" $ do
        exec defs `shouldBe` Left [RepeatedDefinition "foo"]

    describe "given some definitions without a main" $ do
      let defs = [MappyDef (MappyNamedValue "foo") (MappyKeyword "bar")]

      it "errors with a main not found error" $ do
        exec defs `shouldBe` Left [MainNotFound]
