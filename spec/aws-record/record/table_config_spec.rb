# Copyright 2015-2017 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You may not
# use this file except in compliance with the License. A copy of the License is
# located at
#
#     http://aws.amazon.com/apache2.0/
#
# or in the "license" file accompanying this file. This file is distributed on
# an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express
# or implied. See the License for the specific language governing permissions
# and limitations under the License.

require 'spec_helper'

module Aws
  module Record
    describe TableConfig do

      let(:api_requests) { [] }

      def configure_test_client(client)
        requests = api_requests
        client.handle do |context|
          requests << context.params
          @handler.call(context)
        end
        client
      end

      it 'accepts a minimal set of table configuration inputs' do
        cfg = TableConfig.define do |t|
          t.model_class(TestModel)
          t.read_capacity_units(1)
          t.write_capacity_units(1)
          t.client_options(stub_responses: true)
        end
      end

      it 'accepts global secondary indexes in the definition' do
        cfg = TableConfig.define do |t|
          t.model_class(TestModelWithGsi)
          t.read_capacity_units(2)
          t.write_capacity_units(2)
          t.global_secondary_index(:gsi) do |i|
            i.read_capacity_units(1)
            i.write_capacity_units(1)
          end
          t.client_options(stub_responses: true)
        end
      end

      describe "#migrate!" do
        it 'will attempt to create the remote table if it does not exist' do
          cfg = TableConfig.define do |t|
            t.model_class(TestModel)
            t.read_capacity_units(1)
            t.write_capacity_units(1)
            t.client_options(stub_responses: true)
          end
          stub_client = configure_test_client(cfg.client)
          stub_client.stub_responses(
            :describe_table,
            'ResourceNotFoundException',
            { table: { table_status: "ACTIVE" } }
          )
          cfg.migrate!
          expect(api_requests[1]).to eq(
            table_name: "TestModel",
            provisioned_throughput:
            {
              read_capacity_units: 1,
              write_capacity_units: 1
            },
            key_schema: [
              {
                attribute_name: "hk",
                key_type: "HASH"
              },
              {
                attribute_name: "rk",
                key_type: "RANGE"
              }
            ],
            attribute_definitions: [
              {
                attribute_name: "hk",
                attribute_type: "S"
              },
              {
                attribute_name: "rk",
                attribute_type: "S"
              }
            ]
          )
        end

        it 'will update an existing table' do
          cfg = TableConfig.define do |t|
            t.model_class(TestModel)
            t.read_capacity_units(2)
            t.write_capacity_units(1)
            t.client_options(stub_responses: true)
          end
          stub_client = configure_test_client(cfg.client)
          stub_client.stub_responses(
            :describe_table,
            {
              table: {
                attribute_definitions: [
                  {
                    attribute_name: "hk",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "rk",
                    attribute_type: "S"
                  }
                ],
                table_name: "TestModel",
                key_schema: [
                  {
                    attribute_name: "hk",
                    key_type: "HASH"
                  },
                  {
                    attribute_name: "rk",
                    key_type: "RANGE"
                  }
                ],
                provisioned_throughput: {
                  read_capacity_units: 1,
                  write_capacity_units: 1,
                  number_of_decreases_today: 0
                },
                table_status: "ACTIVE"
              }
            },
            { table: { table_status: "ACTIVE" } }
          )
          cfg.migrate!
          expect(api_requests[1]).to eq(
            table_name: "TestModel",
            provisioned_throughput:
            {
              read_capacity_units: 2,
              write_capacity_units: 1
            }
          )
        end

        it 'will validate required configuration values' do
          cfg = TableConfig.define do |t|
            t.client_options(stub_responses: true)
          end
          expect{ cfg.migrate! }.to raise_error(
            Errors::MissingRequiredConfiguration,
            'Missing: model_class, read_capacity_units, write_capacity_units'
          )
        end

        it 'will validate model_class configuration' do
          cfg = TableConfig.define do |t|
            t.read_capacity_units(1)
            t.write_capacity_units(1)
            t.client_options(stub_responses: true)
          end
          expect{ cfg.migrate! }.to raise_error(
            Errors::MissingRequiredConfiguration,
            'Missing: model_class'
          )
        end

        it 'will validate provisioned throughput configuration values' do
          cfg = TableConfig.define do |t|
            t.model_class(TestModel)
            t.client_options(stub_responses: true)
          end
          expect{ cfg.migrate! }.to raise_error(
            Errors::MissingRequiredConfiguration,
            'Missing: read_capacity_units, write_capacity_units'
          )
        end

        context "Global Secondary Indexes" do

          it 'can create a new table with global secondary indexes' do
            cfg = TableConfig.define do |t|
              t.model_class(TestModelWithGsi)
              t.read_capacity_units(2)
              t.write_capacity_units(2)
              t.global_secondary_index(:gsi) do |i|
                i.read_capacity_units(1)
                i.write_capacity_units(1)
              end
              t.client_options(stub_responses: true)
            end
            stub_client = configure_test_client(cfg.client)
            stub_client.stub_responses(
              :describe_table,
              'ResourceNotFoundException',
              { table: { table_status: "ACTIVE" } }
            )
            cfg.migrate!
            expect(api_requests[1]).to eq(
              table_name: "TestModelWithGsi",
              provisioned_throughput:
              {
                read_capacity_units: 2,
                write_capacity_units: 2
              },
              key_schema: [
                {
                  attribute_name: "hk",
                  key_type: "HASH"
                },
                {
                  attribute_name: "rk",
                  key_type: "RANGE"
                }
              ],
              attribute_definitions: [
                {
                  attribute_name: "hk",
                  attribute_type: "S"
                },
                {
                  attribute_name: "rk",
                  attribute_type: "S"
                },
                {
                  attribute_name: "gsi_pk",
                  attribute_type: "S"
                },
                {
                  attribute_name: "gsi_sk",
                  attribute_type: "S"
                }
              ],
              global_secondary_indexes: [
                {
                  index_name: "gsi",
                  key_schema: [
                    {
                      key_type: "HASH",
                      attribute_name: "gsi_pk"
                    },
                    {
                      key_type: "RANGE",
                      attribute_name: "gsi_sk"
                    }
                  ],
                  projection: {
                    projection_type: "INCLUDE",
                    non_key_attributes: ['c', 'b', 'a'] 
                  },
                  provisioned_throughput: {
                    read_capacity_units: 1,
                    write_capacity_units: 1
                  } 
                }
              ]
            )
          end

          it 'can update a table to add global secondary indexes' do
            cfg = TableConfig.define do |t|
              t.model_class(TestModelWithGsi)
              t.read_capacity_units(2)
              t.write_capacity_units(2)
              t.global_secondary_index(:gsi) do |i|
                i.read_capacity_units(1)
                i.write_capacity_units(1)
              end
              t.client_options(stub_responses: true)
            end
            stub_client = configure_test_client(cfg.client)
            stub_client.stub_responses(
              :describe_table,
              {
                table: {
                  attribute_definitions: [
                    {
                      attribute_type: "S",
                      attribute_name: "hk"
                    },
                    {
                      attribute_name: "rk",
                      attribute_type: "S"
                    }
                  ],
                  table_name: "TestModelWithGsi",
                  key_schema: [
                    {
                      attribute_name: "hk",
                      key_type: "HASH"
                    },
                    {
                      attribute_name: "rk",
                      key_type: "RANGE"
                    }
                  ],
                  provisioned_throughput: {
                    read_capacity_units: 2,
                    write_capacity_units: 2,
                    number_of_decreases_today: 0
                  },
                  table_status: "ACTIVE"
                }
              },
              { table: { table_status: "ACTIVE" } }
            )
            cfg.migrate!
            expect(api_requests[1]).to eq(
              table_name: "TestModelWithGsi",
              attribute_definitions: [
                {
                  attribute_name: "gsi_pk",
                  attribute_type: "S"
                },
                {
                  attribute_name: "gsi_sk",
                  attribute_type: "S"
                }
              ],
              global_secondary_index_updates: [
                {
                  create: {
                    index_name: "gsi",
                    key_schema: [
                      {
                        key_type: "HASH",
                        attribute_name: "gsi_pk"
                      },
                      {
                        key_type: "RANGE",
                        attribute_name: "gsi_sk"
                      }
                    ],
                    projection: {
                      projection_type: "INCLUDE",
                      non_key_attributes: ['c', 'b', 'a'] 
                    },
                    provisioned_throughput: {
                      read_capacity_units: 1,
                      write_capacity_units: 1
                    } 
                  }
                }
              ]
            )
          end

          it 'separates throughput and index updates' do
            cfg = TableConfig.define do |t|
              t.model_class(TestModelWithGsi)
              t.read_capacity_units(2)
              t.write_capacity_units(2)
              t.global_secondary_index(:gsi) do |i|
                i.read_capacity_units(1)
                i.write_capacity_units(1)
              end
              t.client_options(stub_responses: true)
            end
            stub_client = configure_test_client(cfg.client)
            stub_client.stub_responses(
              :describe_table,
              {
                table: {
                  attribute_definitions: [
                    {
                      attribute_type: "S",
                      attribute_name: "hk"
                    },
                    {
                      attribute_name: "rk",
                      attribute_type: "S"
                    }
                  ],
                  table_name: "TestModelWithGsi",
                  key_schema: [
                    {
                      attribute_name: "hk",
                      key_type: "HASH"
                    },
                    {
                      attribute_name: "rk",
                      key_type: "RANGE"
                    }
                  ],
                  provisioned_throughput: {
                    read_capacity_units: 1,
                    write_capacity_units: 1,
                    number_of_decreases_today: 0
                  },
                  table_status: "ACTIVE"
                }
              },
              { table: { table_status: "ACTIVE" } }
            )
            cfg.migrate!
            expect(api_requests[1]).to eq(
              table_name: "TestModelWithGsi",
              provisioned_throughput: {
                read_capacity_units: 2,
                write_capacity_units: 2
              }
            )
            expect(api_requests[3]).to eq(
              table_name: "TestModelWithGsi",
              attribute_definitions: [
                {
                  attribute_name: "gsi_pk",
                  attribute_type: "S"
                },
                {
                  attribute_name: "gsi_sk",
                  attribute_type: "S"
                }
              ],
              global_secondary_index_updates: [
                {
                  create: {
                    index_name: "gsi",
                    key_schema: [
                      {
                        key_type: "HASH",
                        attribute_name: "gsi_pk"
                      },
                      {
                        key_type: "RANGE",
                        attribute_name: "gsi_sk"
                      }
                    ],
                    projection: {
                      projection_type: "INCLUDE",
                      non_key_attributes: ['c', 'b', 'a'] 
                    },
                    provisioned_throughput: {
                      read_capacity_units: 1,
                      write_capacity_units: 1
                    } 
                  }
                }
              ]
            )
          end

          it 'correctly reuses attribute definitions during gsi creation' do
            cfg = TableConfig.define do |t|
              t.model_class(TestModelWithGsi2)
              t.read_capacity_units(2)
              t.write_capacity_units(2)
              t.global_secondary_index(:gsi) do |i|
                i.read_capacity_units(1)
                i.write_capacity_units(1)
              end
              t.client_options(stub_responses: true)
            end
            stub_client = configure_test_client(cfg.client)
            stub_client.stub_responses(
              :describe_table,
              {
                table: {
                  attribute_definitions: [
                    {
                      attribute_type: "S",
                      attribute_name: "hk"
                    },
                    {
                      attribute_name: "rk",
                      attribute_type: "S"
                    }
                  ],
                  table_name: "TestModelWithGsi2",
                  key_schema: [
                    {
                      attribute_name: "hk",
                      key_type: "HASH"
                    },
                    {
                      attribute_name: "rk",
                      key_type: "RANGE"
                    }
                  ],
                  provisioned_throughput: {
                    read_capacity_units: 2,
                    write_capacity_units: 2,
                    number_of_decreases_today: 0
                  },
                  table_status: "ACTIVE"
                }
              },
              { table: { table_status: "ACTIVE" } }
            )
            cfg.migrate!
            expect(api_requests[1]).to eq(
              table_name: "TestModelWithGsi2",
              attribute_definitions: [
                {
                  attribute_name: "hk",
                  attribute_type: "S"
                },
                {
                  attribute_name: "gsi_sk",
                  attribute_type: "S"
                }
              ],
              global_secondary_index_updates: [
                {
                  create: {
                    index_name: "gsi",
                    key_schema: [
                      {
                        key_type: "HASH",
                        attribute_name: "hk"
                      },
                      {
                        key_type: "RANGE",
                        attribute_name: "gsi_sk"
                      }
                    ],
                    projection: {
                      projection_type: "ALL"
                    },
                    provisioned_throughput: {
                      read_capacity_units: 1,
                      write_capacity_units: 1
                    } 
                  }
                }
              ]
            )
          end

          it 'can update a table to modify a global secondary index' do
            cfg = TableConfig.define do |t|
              t.model_class(TestModelWithGsi2)
              t.read_capacity_units(2)
              t.write_capacity_units(2)
              t.global_secondary_index(:gsi) do |i|
                i.read_capacity_units(2)
                i.write_capacity_units(2)
              end
              t.client_options(stub_responses: true)
            end
            stub_client = configure_test_client(cfg.client)
            stub_client.stub_responses(
              :describe_table,
              {
                table: {
                  table_status: "ACTIVE",
                  attribute_definitions: [
                    {
                      attribute_name: "hk",
                      attribute_type: "S"
                    },
                    {
                      attribute_name: "rk",
                      attribute_type: "S"
                    },
                    {
                      attribute_name: "gsi_pk",
                      attribute_type: "S"
                    },
                    {
                      attribute_name: "gsi_sk",
                      attribute_type: "S"
                    }
                  ],
                  table_name: "TestModel",
                  key_schema: [
                    {
                      attribute_name: "hk",
                      key_type: "HASH"
                    },
                    {
                      attribute_name: "rk",
                      key_type: "RANGE"
                    }
                  ],
                  provisioned_throughput: {
                    read_capacity_units: 2,
                    write_capacity_units: 2,
                    number_of_decreases_today: 0
                  },
                  global_secondary_indexes: [
                    {
                      index_name: "gsi",
                      key_schema: [
                        {
                          key_type: "RANGE",
                          attribute_name: "gsi_sk"
                        },
                        {
                          key_type: "HASH",
                          attribute_name: "gsi_pk"
                        }
                      ],
                      projection: {
                        projection_type: "INCLUDE",
                        non_key_attributes: ["a", "b", "c"]
                      },
                      item_count: 0,
                      index_status: "ACTIVE",
                      backfilling: false,
                      provisioned_throughput: {
                        read_capacity_units: 1,
                        write_capacity_units: 1,
                        number_of_decreases_today: 0
                      }
                    }
                  ]
                }
              }
            )
            cfg.migrate!
            expect(api_requests[1]).to eq(
              table_name: "TestModelWithGsi2",
              global_secondary_index_updates: [
                {
                  update: {
                    index_name: "gsi",
                    provisioned_throughput: {
                      read_capacity_units: 2,
                      write_capacity_units: 2
                    } 
                  }
                }
              ]
            )
          end

          it 'can handle multiple global secondary index updates at once' do
            cfg = TableConfig.define do |t|
              t.model_class(TestModelWithGsi3)
              t.read_capacity_units(2)
              t.write_capacity_units(2)
              t.global_secondary_index(:gsi) do |i|
                i.read_capacity_units(2)
                i.write_capacity_units(2)
              end
              t.global_secondary_index(:gsi2) do |i|
                i.read_capacity_units(2)
                i.write_capacity_units(2)
              end
              t.client_options(stub_responses: true)
            end
            stub_client = configure_test_client(cfg.client)
            stub_client.stub_responses(
              :describe_table,
              {
                table: {
                  attribute_definitions: [
                    {
                      attribute_type: "S",
                      attribute_name: "hk"
                    },
                    {
                      attribute_name: "rk",
                      attribute_type: "S"
                    },
                    {
                      attribute_name: "gsi_sk",
                      attribute_type: "S"
                    }
                  ],
                  table_name: "TestModelWithGsi3",
                  key_schema: [
                    {
                      attribute_name: "hk",
                      key_type: "HASH"
                    },
                    {
                      attribute_name: "rk",
                      key_type: "RANGE"
                    }
                  ],
                  provisioned_throughput: {
                    read_capacity_units: 2,
                    write_capacity_units: 2,
                    number_of_decreases_today: 0
                  },
                  global_secondary_indexes: [
                    {
                      index_name: "gsi",
                      key_schema: [
                        {
                          key_type: "RANGE",
                          attribute_name: "gsi_sk"
                        },
                        {
                          key_type: "HASH",
                          attribute_name: "hk"
                        }
                      ],
                      projection: {
                        projection_type: "ALL"
                      },
                      item_count: 0,
                      index_status: "ACTIVE",
                      backfilling: false,
                      provisioned_throughput: {
                        read_capacity_units: 1,
                        write_capacity_units: 1,
                        number_of_decreases_today: 0
                      }
                    }
                  ],
                  table_status: "ACTIVE"
                }
              },
              { table: { table_status: "ACTIVE" } }
            )
            cfg.migrate!
            expect(api_requests[1]).to eq(
              table_name: "TestModelWithGsi3",
              attribute_definitions: [
                {
                  attribute_name: "gsi_pk",
                  attribute_type: "S"
                },
                {
                  attribute_name: "gsi_sk",
                  attribute_type: "S"
                }
              ],
              global_secondary_index_updates: [
                {
                  create: {
                    index_name: "gsi2",
                    key_schema: [
                      {
                        key_type: "HASH",
                        attribute_name: "gsi_pk"
                      },
                      {
                        key_type: "RANGE",
                        attribute_name: "gsi_sk"
                      }
                    ],
                    projection: {
                      projection_type: "ALL"
                    },
                    provisioned_throughput: {
                      read_capacity_units: 2,
                      write_capacity_units: 2
                    } 
                  }
                },
                {
                  update: {
                    index_name: "gsi",
                    provisioned_throughput: {
                      read_capacity_units: 2,
                      write_capacity_units: 2
                    }
                  }
                }
              ]
            )
          end

        end

      end

      describe '#compatible?' do

        it 'compares against a #describe_table call' do
          cfg = TableConfig.define do |t|
            t.model_class(TestModel)
            t.read_capacity_units(1)
            t.write_capacity_units(1)
            t.client_options(stub_responses: true)
          end
          stub_client = configure_test_client(cfg.client)
          stub_client.stub_responses(
            :describe_table,
            {
              table: {
                attribute_definitions: [
                  {
                    attribute_name: "hk",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "rk",
                    attribute_type: "S"
                  }
                ],
                table_name: "TestModel",
                key_schema: [
                  {
                    attribute_name: "hk",
                    key_type: "HASH"
                  },
                  {
                    attribute_name: "rk",
                    key_type: "RANGE"
                  }
                ],
                provisioned_throughput: {
                  read_capacity_units: 1,
                  write_capacity_units: 1,
                  number_of_decreases_today: 0
                }
              }
            }
          )
          expect(cfg.compatible?).to be_truthy
        end

        it 'fails when a configured value does not match' do
          cfg = TableConfig.define do |t|
            t.model_class(TestModel)
            t.read_capacity_units(1)
            t.write_capacity_units(1)
            t.client_options(stub_responses: true)
          end
          stub_client = configure_test_client(cfg.client)
          stub_client.stub_responses(
            :describe_table,
            {
              table: {
                attribute_definitions: [
                  {
                    attribute_name: "hk",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "rk",
                    attribute_type: "S"
                  }
                ],
                table_name: "TestModel",
                key_schema: [
                  {
                    attribute_name: "hk",
                    key_type: "HASH"
                  },
                  {
                    attribute_name: "rk",
                    key_type: "RANGE"
                  }
                ],
                provisioned_throughput: {
                  read_capacity_units: 2,
                  write_capacity_units: 1
                }
              }
            }
          )
          expect(cfg.compatible?).to be_falsy
        end

        it 'fails when the remote model does not match' do
          cfg = TableConfig.define do |t|
            t.model_class(TestModel)
            t.read_capacity_units(1)
            t.write_capacity_units(1)
            t.client_options(stub_responses: true)
          end
          stub_client = configure_test_client(cfg.client)
          stub_client.stub_responses(
            :describe_table,
            {
              table: {
                attribute_definitions: [
                  {
                    attribute_name: "hashkey",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "rk",
                    attribute_type: "S"
                  }
                ],
                table_name: "TestModel",
                key_schema: [
                  {
                    attribute_name: "hashkey",
                    key_type: "HASH"
                  },
                  {
                    attribute_name: "rk",
                    key_type: "RANGE"
                  }
                ],
                provisioned_throughput: {
                  read_capacity_units: 1,
                  write_capacity_units: 1
                }
              }
            }
          )
          expect(cfg.compatible?).to be_falsy
        end

        it 'matches with a superset of attribute definitions' do
          cfg = TableConfig.define do |t|
            t.model_class(TestModel)
            t.read_capacity_units(1)
            t.write_capacity_units(1)
            t.client_options(stub_responses: true)
          end
          stub_client = configure_test_client(cfg.client)
          stub_client.stub_responses(
            :describe_table,
            {
              table: {
                attribute_definitions: [
                  {
                    attribute_name: "hk",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "bacon",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "rk",
                    attribute_type: "S"
                  }
                ],
                table_name: "TestModel",
                key_schema: [
                  {
                    attribute_name: "hk",
                    key_type: "HASH"
                  },
                  {
                    attribute_name: "rk",
                    key_type: "RANGE"
                  }
                ],
                provisioned_throughput: {
                  read_capacity_units: 1,
                  write_capacity_units: 1
                }
              }
            }
          )
          expect(cfg.compatible?).to be_truthy
        end

        it 'returns false if the table does not exist' do
          cfg = TableConfig.define do |t|
            t.model_class(TestModel)
            t.read_capacity_units(1)
            t.write_capacity_units(1)
            t.client_options(stub_responses: true)
          end
          stub_client = configure_test_client(cfg.client)
          stub_client.stub_responses(
            :describe_table,
            'ResourceNotFoundException'
          )
          expect(cfg.compatible?).to be_falsy
        end

        it 'returns false if a global secondary index is missing' do
          cfg = TableConfig.define do |t|
            t.model_class(TestModelWithGsi)
            t.read_capacity_units(2)
            t.write_capacity_units(2)
            t.global_secondary_index(:gsi) do |i|
              i.read_capacity_units(1)
              i.write_capacity_units(1)
            end
            t.client_options(stub_responses: true)
          end
          stub_client = configure_test_client(cfg.client)
          stub_client.stub_responses(
            :describe_table,
            {
              table: {
                attribute_definitions: [
                  {
                    attribute_name: "hk",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "rk",
                    attribute_type: "S"
                  }
                ],
                table_name: "TestModel",
                key_schema: [
                  {
                    attribute_name: "hk",
                    key_type: "HASH"
                  },
                  {
                    attribute_name: "rk",
                    key_type: "RANGE"
                  }
                ],
                provisioned_throughput: {
                  read_capacity_units: 2,
                  write_capacity_units: 2,
                  number_of_decreases_today: 0
                }
              }
            }
          )
          expect(cfg.compatible?).to be_falsy
        end

        it 'returns true if global secondary indexes are present and match' do
          cfg = TableConfig.define do |t|
            t.model_class(TestModelWithGsi)
            t.read_capacity_units(2)
            t.write_capacity_units(2)
            t.global_secondary_index(:gsi) do |i|
              i.read_capacity_units(1)
              i.write_capacity_units(1)
            end
            t.client_options(stub_responses: true)
          end
          stub_client = configure_test_client(cfg.client)
          stub_client.stub_responses(
            :describe_table,
            {
              table: {
                attribute_definitions: [
                  {
                    attribute_name: "hk",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "rk",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "gsi_pk",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "gsi_sk",
                    attribute_type: "S"
                  }
                ],
                table_name: "TestModel",
                key_schema: [
                  {
                    attribute_name: "hk",
                    key_type: "HASH"
                  },
                  {
                    attribute_name: "rk",
                    key_type: "RANGE"
                  }
                ],
                provisioned_throughput: {
                  read_capacity_units: 2,
                  write_capacity_units: 2,
                  number_of_decreases_today: 0
                },
                global_secondary_indexes: [
                  {
                    index_name: "gsi",
                    key_schema: [
                      {
                        key_type: "RANGE",
                        attribute_name: "gsi_sk"
                      },
                      {
                        key_type: "HASH",
                        attribute_name: "gsi_pk"
                      }
                    ],
                    projection: {
                      projection_type: "INCLUDE",
                      non_key_attributes: ["a", "b", "c"]
                    },
                    item_count: 0,
                    index_status: "ACTIVE",
                    backfilling: false,
                    provisioned_throughput: {
                      read_capacity_units: 1,
                      write_capacity_units: 1,
                      number_of_decreases_today: 0
                    }
                  }
                ]
              }
            }
          )
          expect(cfg.compatible?).to be_truthy
        end

        it 'returns true if superset of global secondary indexes are present' do
          cfg = TableConfig.define do |t|
            t.model_class(TestModelWithGsi)
            t.read_capacity_units(2)
            t.write_capacity_units(2)
            t.global_secondary_index(:gsi) do |i|
              i.read_capacity_units(1)
              i.write_capacity_units(1)
            end
            t.client_options(stub_responses: true)
          end
          stub_client = configure_test_client(cfg.client)
          stub_client.stub_responses(
            :describe_table,
            {
              table: {
                attribute_definitions: [
                  {
                    attribute_name: "hk",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "rk",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "gsi_pk",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "gsi_sk",
                    attribute_type: "S"
                  }
                ],
                table_name: "TestModel",
                key_schema: [
                  {
                    attribute_name: "hk",
                    key_type: "HASH"
                  },
                  {
                    attribute_name: "rk",
                    key_type: "RANGE"
                  }
                ],
                provisioned_throughput: {
                  read_capacity_units: 2,
                  write_capacity_units: 2,
                  number_of_decreases_today: 0
                },
                global_secondary_indexes: [
                  {
                    index_name: "gsi",
                    key_schema: [
                      {
                        key_type: "RANGE",
                        attribute_name: "gsi_sk"
                      },
                      {
                        key_type: "HASH",
                        attribute_name: "gsi_pk"
                      }
                    ],
                    projection: {
                      projection_type: "INCLUDE",
                      non_key_attributes: ["a", "b", "c"]
                    },
                    item_count: 0,
                    index_status: "ACTIVE",
                    backfilling: false,
                    provisioned_throughput: {
                      read_capacity_units: 1,
                      write_capacity_units: 1,
                      number_of_decreases_today: 0
                    }
                  },
                  {
                    index_name: "sir_not_appearing_in_this_model",
                    key_schema: [
                      {
                        key_type: "RANGE",
                        attribute_name: "gsi_sk"
                      },
                      {
                        key_type: "HASH",
                        attribute_name: "gsi_pk"
                      }
                    ],
                    projection: {
                      projection_type: "INCLUDE",
                      non_key_attributes: ["a", "b", "c"]
                    },
                    item_count: 0,
                    index_status: "ACTIVE",
                    backfilling: false,
                    provisioned_throughput: {
                      read_capacity_units: 1,
                      write_capacity_units: 1,
                      number_of_decreases_today: 0
                    }
                  }
                ]
              }
            }
          )
          expect(cfg.compatible?).to be_truthy
        end

        it 'returns false if there is an attribute definition mismatch' do
          cfg = TableConfig.define do |t|
            t.model_class(TestModelWithGsi)
            t.read_capacity_units(2)
            t.write_capacity_units(2)
            t.global_secondary_index(:gsi) do |i|
              i.read_capacity_units(1)
              i.write_capacity_units(1)
            end
            t.client_options(stub_responses: true)
          end
          stub_client = configure_test_client(cfg.client)
          stub_client.stub_responses(
            :describe_table,
            {
              table: {
                attribute_definitions: [
                  {
                    attribute_name: "hk",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "rk",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "gsi_pk",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "gsi_rk",
                    attribute_type: "S"
                  }
                ],
                table_name: "TestModel",
                key_schema: [
                  {
                    attribute_name: "hk",
                    key_type: "HASH"
                  },
                  {
                    attribute_name: "rk",
                    key_type: "RANGE"
                  }
                ],
                provisioned_throughput: {
                  read_capacity_units: 2,
                  write_capacity_units: 2,
                  number_of_decreases_today: 0
                },
                global_secondary_indexes: [
                  {
                    index_name: "gsi",
                    key_schema: [
                      {
                        key_type: "RANGE",
                        attribute_name: "gsi_sk"
                      },
                      {
                        key_type: "HASH",
                        attribute_name: "gsi_pk"
                      }
                    ],
                    projection: {
                      projection_type: "INCLUDE",
                      non_key_attributes: ["a", "b", "c"]
                    },
                    item_count: 0,
                    index_status: "ACTIVE",
                    backfilling: false,
                    provisioned_throughput: {
                      read_capacity_units: 1,
                      write_capacity_units: 1,
                      number_of_decreases_today: 0
                    }
                  }
                ]
              }
            }
          )
          expect(cfg.compatible?).to be_falsy
        end

      end

      describe '#exact_match?' do

        it 'compares against a #describe_table call' do
          cfg = TableConfig.define do |t|
            t.model_class(TestModel)
            t.read_capacity_units(1)
            t.write_capacity_units(1)
            t.client_options(stub_responses: true)
          end
          stub_client = configure_test_client(cfg.client)
          stub_client.stub_responses(
            :describe_table,
            {
              table: {
                attribute_definitions: [
                  {
                    attribute_name: "rk",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "hk",
                    attribute_type: "S"
                  }
                ],
                table_name: "TestModel",
                key_schema: [
                  {
                    attribute_name: "rk",
                    key_type: "RANGE"
                  },
                  {
                    attribute_name: "hk",
                    key_type: "HASH"
                  }
                ],
                provisioned_throughput: {
                  read_capacity_units: 1,
                  write_capacity_units: 1,
                  number_of_decreases_today: 0
                }
              }
            }
          )
          expect(cfg.exact_match?).to be_truthy
        end

        it 'fails when a configured value does not match' do
          cfg = TableConfig.define do |t|
            t.model_class(TestModel)
            t.read_capacity_units(1)
            t.write_capacity_units(1)
            t.client_options(stub_responses: true)
          end
          stub_client = configure_test_client(cfg.client)
          stub_client.stub_responses(
            :describe_table,
            {
              table: {
                attribute_definitions: [
                  {
                    attribute_name: "hk",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "rk",
                    attribute_type: "S"
                  }
                ],
                table_name: "TestModel",
                key_schema: [
                  {
                    attribute_name: "hk",
                    key_type: "HASH"
                  },
                  {
                    attribute_name: "rk",
                    key_type: "RANGE"
                  }
                ],
                provisioned_throughput: {
                  read_capacity_units: 2,
                  write_capacity_units: 1
                }
              }
            }
          )
          expect(cfg.exact_match?).to be_falsy
        end

        it 'fails when the remote model does not match' do
          cfg = TableConfig.define do |t|
            t.model_class(TestModel)
            t.read_capacity_units(1)
            t.write_capacity_units(1)
            t.client_options(stub_responses: true)
          end
          stub_client = configure_test_client(cfg.client)
          stub_client.stub_responses(
            :describe_table,
            {
              table: {
                attribute_definitions: [
                  {
                    attribute_name: "hashkey",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "rk",
                    attribute_type: "S"
                  }
                ],
                table_name: "TestModel",
                key_schema: [
                  {
                    attribute_name: "hashkey",
                    key_type: "HASH"
                  },
                  {
                    attribute_name: "rk",
                    key_type: "RANGE"
                  }
                ],
                provisioned_throughput: {
                  read_capacity_units: 1,
                  write_capacity_units: 1
                }
              }
            }
          )
          expect(cfg.exact_match?).to be_falsy
        end

        it 'does not match with a superset of attribute definitions' do
          cfg = TableConfig.define do |t|
            t.model_class(TestModel)
            t.read_capacity_units(1)
            t.write_capacity_units(1)
            t.client_options(stub_responses: true)
          end
          stub_client = configure_test_client(cfg.client)
          stub_client.stub_responses(
            :describe_table,
            {
              table: {
                attribute_definitions: [
                  {
                    attribute_name: "hk",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "bacon",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "rk",
                    attribute_type: "S"
                  }
                ],
                table_name: "TestModel",
                key_schema: [
                  {
                    attribute_name: "hk",
                    key_type: "HASH"
                  },
                  {
                    attribute_name: "rk",
                    key_type: "RANGE"
                  }
                ],
                provisioned_throughput: {
                  read_capacity_units: 1,
                  write_capacity_units: 1
                }
              }
            }
          )
          expect(cfg.exact_match?).to be_falsy
        end

        it 'returns false if the table does not exist' do
          cfg = TableConfig.define do |t|
            t.model_class(TestModel)
            t.read_capacity_units(1)
            t.write_capacity_units(1)
            t.client_options(stub_responses: true)
          end
          stub_client = configure_test_client(cfg.client)
          stub_client.stub_responses(
            :describe_table,
            'ResourceNotFoundException'
          )
          expect(cfg.exact_match?).to be_falsy
        end
        
        it 'returns false if a global secondary index is missing' do
          cfg = TableConfig.define do |t|
            t.model_class(TestModelWithGsi)
            t.read_capacity_units(2)
            t.write_capacity_units(2)
            t.global_secondary_index(:gsi) do |i|
              i.read_capacity_units(1)
              i.write_capacity_units(1)
            end
            t.client_options(stub_responses: true)
          end
          stub_client = configure_test_client(cfg.client)
          stub_client.stub_responses(
            :describe_table,
            {
              table: {
                attribute_definitions: [
                  {
                    attribute_name: "hk",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "rk",
                    attribute_type: "S"
                  }
                ],
                table_name: "TestModel",
                key_schema: [
                  {
                    attribute_name: "hk",
                    key_type: "HASH"
                  },
                  {
                    attribute_name: "rk",
                    key_type: "RANGE"
                  }
                ],
                provisioned_throughput: {
                  read_capacity_units: 2,
                  write_capacity_units: 2,
                  number_of_decreases_today: 0
                }
              }
            }
          )
          expect(cfg.exact_match?).to be_falsy
        end

        it 'returns true if global secondary indexes are present and match' do
          cfg = TableConfig.define do |t|
            t.model_class(TestModelWithGsi)
            t.read_capacity_units(2)
            t.write_capacity_units(2)
            t.global_secondary_index(:gsi) do |i|
              i.read_capacity_units(1)
              i.write_capacity_units(1)
            end
            t.client_options(stub_responses: true)
          end
          stub_client = configure_test_client(cfg.client)
          stub_client.stub_responses(
            :describe_table,
            {
              table: {
                attribute_definitions: [
                  {
                    attribute_name: "hk",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "rk",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "gsi_pk",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "gsi_sk",
                    attribute_type: "S"
                  }
                ],
                table_name: "TestModel",
                key_schema: [
                  {
                    attribute_name: "hk",
                    key_type: "HASH"
                  },
                  {
                    attribute_name: "rk",
                    key_type: "RANGE"
                  }
                ],
                provisioned_throughput: {
                  read_capacity_units: 2,
                  write_capacity_units: 2,
                  number_of_decreases_today: 0
                },
                global_secondary_indexes: [
                  {
                    index_name: "gsi",
                    key_schema: [
                      {
                        key_type: "RANGE",
                        attribute_name: "gsi_sk"
                      },
                      {
                        key_type: "HASH",
                        attribute_name: "gsi_pk"
                      }
                    ],
                    projection: {
                      projection_type: "INCLUDE",
                      non_key_attributes: ["a", "b", "c"]
                    },
                    item_count: 0,
                    index_status: "ACTIVE",
                    backfilling: false,
                    provisioned_throughput: {
                      read_capacity_units: 1,
                      write_capacity_units: 1,
                      number_of_decreases_today: 0
                    }
                  }
                ]
              }
            }
          )
          expect(cfg.exact_match?).to be_truthy
        end

        it 'returns false if superset of global secondary indexes present' do
          cfg = TableConfig.define do |t|
            t.model_class(TestModelWithGsi)
            t.read_capacity_units(2)
            t.write_capacity_units(2)
            t.global_secondary_index(:gsi) do |i|
              i.read_capacity_units(1)
              i.write_capacity_units(1)
            end
            t.client_options(stub_responses: true)
          end
          stub_client = configure_test_client(cfg.client)
          stub_client.stub_responses(
            :describe_table,
            {
              table: {
                attribute_definitions: [
                  {
                    attribute_name: "hk",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "rk",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "gsi_pk",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "gsi_sk",
                    attribute_type: "S"
                  }
                ],
                table_name: "TestModel",
                key_schema: [
                  {
                    attribute_name: "hk",
                    key_type: "HASH"
                  },
                  {
                    attribute_name: "rk",
                    key_type: "RANGE"
                  }
                ],
                provisioned_throughput: {
                  read_capacity_units: 2,
                  write_capacity_units: 2,
                  number_of_decreases_today: 0
                },
                global_secondary_indexes: [
                  {
                    index_name: "gsi",
                    key_schema: [
                      {
                        key_type: "RANGE",
                        attribute_name: "gsi_sk"
                      },
                      {
                        key_type: "HASH",
                        attribute_name: "gsi_pk"
                      }
                    ],
                    projection: {
                      projection_type: "INCLUDE",
                      non_key_attributes: ["a", "b", "c"]
                    },
                    item_count: 0,
                    index_status: "ACTIVE",
                    backfilling: false,
                    provisioned_throughput: {
                      read_capacity_units: 1,
                      write_capacity_units: 1,
                      number_of_decreases_today: 0
                    }
                  },
                  {
                    index_name: "sir_not_appearing_in_this_model",
                    key_schema: [
                      {
                        key_type: "RANGE",
                        attribute_name: "gsi_sk"
                      },
                      {
                        key_type: "HASH",
                        attribute_name: "gsi_pk"
                      }
                    ],
                    projection: {
                      projection_type: "INCLUDE",
                      non_key_attributes: ["a", "b", "c"]
                    },
                    item_count: 0,
                    index_status: "ACTIVE",
                    backfilling: false,
                    provisioned_throughput: {
                      read_capacity_units: 1,
                      write_capacity_units: 1,
                      number_of_decreases_today: 0
                    }
                  }
                ]
              }
            }
          )
          expect(cfg.exact_match?).to be_falsy
        end

        it 'returns false if there is an attribute definition mismatch' do
          cfg = TableConfig.define do |t|
            t.model_class(TestModelWithGsi)
            t.read_capacity_units(2)
            t.write_capacity_units(2)
            t.global_secondary_index(:gsi) do |i|
              i.read_capacity_units(1)
              i.write_capacity_units(1)
            end
            t.client_options(stub_responses: true)
          end
          stub_client = configure_test_client(cfg.client)
          stub_client.stub_responses(
            :describe_table,
            {
              table: {
                attribute_definitions: [
                  {
                    attribute_name: "hk",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "rk",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "gsi_pk",
                    attribute_type: "S"
                  },
                  {
                    attribute_name: "gsi_rk",
                    attribute_type: "S"
                  }
                ],
                table_name: "TestModel",
                key_schema: [
                  {
                    attribute_name: "hk",
                    key_type: "HASH"
                  },
                  {
                    attribute_name: "rk",
                    key_type: "RANGE"
                  }
                ],
                provisioned_throughput: {
                  read_capacity_units: 2,
                  write_capacity_units: 2,
                  number_of_decreases_today: 0
                },
                global_secondary_indexes: [
                  {
                    index_name: "gsi",
                    key_schema: [
                      {
                        key_type: "RANGE",
                        attribute_name: "gsi_sk"
                      },
                      {
                        key_type: "HASH",
                        attribute_name: "gsi_pk"
                      }
                    ],
                    projection: {
                      projection_type: "INCLUDE",
                      non_key_attributes: ["a", "b", "c"]
                    },
                    item_count: 0,
                    index_status: "ACTIVE",
                    backfilling: false,
                    provisioned_throughput: {
                      read_capacity_units: 1,
                      write_capacity_units: 1,
                      number_of_decreases_today: 0
                    }
                  }
                ]
              }
            }
          )
          expect(cfg.exact_match?).to be_falsy
        end

      end

      context "TTL Attributes" do
        it 'raises an exception when TTL is applied to a missing attribute' do
          expect {
            TableConfig.define do |t|
              t.model_class(TestModelWithTtl)
              t.read_capacity_units(1)
              t.write_capacity_units(1)
              t.ttl_attribute(:bizarro_ttl)
              t.client_options(stub_responses: true)
            end
          }.to raise_error(ArgumentError)
        end

        it 'applies TTL attribute settings' do
          cfg = TableConfig.define do |t|
            t.model_class(TestModelWithTtl)
            t.read_capacity_units(1)
            t.write_capacity_units(1)
            t.ttl_attribute(:ttl)
            t.client_options(stub_responses: true)
          end
          stub_client = configure_test_client(cfg.client)
          stub_client.stub_responses(
            :describe_table,
            'ResourceNotFoundException',
            { table: { table_status: "ACTIVE" } }
          )
          cfg.migrate!
          expect(api_requests[1]).to eq(
            table_name: "TestModelWithTtl",
            provisioned_throughput:
            {
              read_capacity_units: 1,
              write_capacity_units: 1
            },
            key_schema: [
              {
                attribute_name: "hk",
                key_type: "HASH"
              },
              {
                attribute_name: "rk",
                key_type: "RANGE"
              }
            ],
            attribute_definitions: [
              {
                attribute_name: "hk",
                attribute_type: "S"
              },
              {
                attribute_name: "rk",
                attribute_type: "S"
              }
            ]
          )
          expect(api_requests[4]).to eq(
            table_name: "TestModelWithTtl",
            time_to_live_specification: {
              enabled: true,
              attribute_name: "TimeToLive"
            }
          )
        end
      end

    end
  end
end

class TestModel
  include Aws::Record

  string_attr :hk, hash_key: true
  string_attr :rk, range_key: true
end

class TestModelWithGsi
  include Aws::Record

  string_attr :hk, hash_key: true
  string_attr :rk, range_key: true
  string_attr :gsi_pk
  string_attr :gsi_sk
  string_attr :a
  string_attr :b
  string_attr :c
  global_secondary_index(
    :gsi,
    hash_key:  :gsi_pk,
    range_key: :gsi_sk,
    projection: {
      projection_type: "INCLUDE",
      non_key_attributes: ["c", "b", "a"]
    }
  )
end

class TestModelWithGsi2
  include Aws::Record

  string_attr :hk, hash_key: true
  string_attr :rk, range_key: true
  string_attr :gsi_sk
  global_secondary_index(
    :gsi,
    hash_key:  :hk,
    range_key: :gsi_sk,
    projection: {
      projection_type: "ALL"
    }
  )
end

class TestModelWithGsi3
  include Aws::Record

  string_attr :hk, hash_key: true
  string_attr :rk, range_key: true
  string_attr :gsi_pk
  string_attr :gsi_sk
  global_secondary_index(
    :gsi,
    hash_key:  :hk,
    range_key: :gsi_sk,
    projection: {
      projection_type: "ALL"
    }
  )
  global_secondary_index(
    :gsi2,
    hash_key:  :gsi_pk,
    range_key: :gsi_sk,
    projection: {
      projection_type: "ALL"
    }
  )
end

class TestModelWithTtl
  include Aws::Record

  string_attr :hk, hash_key: true
  string_attr :rk, range_key: true
  epoch_time_attr :ttl, database_attribute_name: "TimeToLive"
end
